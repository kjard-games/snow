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
const buildings = @import("buildings.zig");

const Character = character.Character;
const Skill = character.Skill;
const MovementIntent = movement.MovementIntent;
const EntityId = entity_types.EntityId;
const Position = position.Position;
const TerrainGrid = terrain_mod.TerrainGrid;
const VFXManager = vfx.VFXManager;
const MatchTelemetry = telemetry.MatchTelemetry;
const BuildingManager = buildings.BuildingManager;

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

    // ========== LAST STAND SYSTEM ==========
    /// Max time to kite before triggering last stand (3 seconds)
    pub const MAX_KITE_TIME_MS: u32 = 3000;

    /// Team health ratio threshold - if enemy team health drops below this fraction
    /// of player team health, trigger last stand (fight is hopeless)
    pub const LAST_STAND_HEALTH_RATIO: f32 = 0.3;

    /// If outnumbered by this many or more, trigger last stand
    pub const LAST_STAND_OUTNUMBER_THRESHOLD: i32 = 2;

    // ========== ENGAGEMENT SYSTEM ==========

    /// Default aggro radius - how close player must be to trigger combat
    pub const AGGRO_RADIUS: f32 = 150.0;

    /// Default leash radius - how far enemies will chase before returning
    pub const LEASH_RADIUS: f32 = 400.0;

    /// Social aggro radius - enemies within this range join when ally is pulled
    pub const SOCIAL_AGGRO_RADIUS: f32 = 100.0;

    /// Alert duration before engaging (dramatic pause)
    pub const ALERT_DURATION_MS: u32 = 500;

    /// Time to wait at spawn before resetting health
    pub const RESET_DELAY_MS: u32 = 3000;

    /// Speed multiplier when leashing back to spawn
    pub const LEASH_SPEED_MULTIPLIER: f32 = 1.5;
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
// ENGAGEMENT STATE - Aggro and Combat Engagement (GW1-style)
// ============================================================================

pub const EngagementState = enum {
    /// Not in combat, following patrol path or idle
    idle,

    /// Player detected within aggro radius, transitioning to combat
    alerted,

    /// Actively engaged in combat
    engaged,

    /// Target escaped beyond leash radius, returning to spawn
    leashing,

    /// Returned to spawn point, resetting health/skills
    resetting,
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

    // ========== LAST STAND SYSTEM ==========
    /// When true, AI stops retreating and fights to the death
    /// Triggered when the fight is clearly lost (outnumbered, low team health)
    last_stand: bool = false,

    /// Time spent kiting (resets when not kiting). After threshold, triggers last stand.
    kite_time_ms: u32 = 0,

    // ========== ENGAGEMENT SYSTEM ==========

    /// Current engagement state (for dungeon AI)
    engagement: EngagementState = .idle,

    /// Original spawn position (for leashing/resetting)
    spawn_position: ?rl.Vector3 = null,

    /// Aggro radius override (0 = use default from encounter)
    aggro_radius: f32 = 0.0,

    /// Leash radius override (0 = use default from encounter)
    leash_radius: f32 = 0.0,

    /// Wave index this AI belongs to (for link pulls)
    wave_index: u8 = 0,

    /// Time spent in current engagement state (for alert delays, reset timers)
    engagement_timer_ms: u32 = 0,

    /// Entity that pulled aggro (for returning to correct spawn)
    aggro_source_id: ?EntityId = null,

    /// Has this AI been pulled this encounter? (for respawn logic)
    was_pulled: bool = false,

    // ========== BOSS PHASE SYSTEM ==========

    /// Current phase index (for bosses)
    current_phase: u8 = 0,

    /// Phase triggers that have fired (bitfield, supports up to 8 phases)
    triggered_phases: u8 = 0,

    /// Time in combat (for time-based phase triggers)
    combat_time_ms: u32 = 0,

    /// Adds killed count (for add-based phase triggers)
    adds_killed: u8 = 0,

    pub fn init(pos: Position) AIState {
        return .{
            .role = AIRole.fromPosition(pos),
            .formation = FormationRole.fromPosition(pos),
        };
    }

    /// Initialize for encounter-based AI with spawn position
    pub fn initForEncounter(pos: Position, spawn_pos: rl.Vector3, wave_idx: u8) AIState {
        return .{
            .role = AIRole.fromPosition(pos),
            .formation = FormationRole.fromPosition(pos),
            .spawn_position = spawn_pos,
            .wave_index = wave_idx,
            .engagement = .idle,
        };
    }

    /// Check if AI is in an active combat state
    pub fn isInCombat(self: *const AIState) bool {
        return self.engagement == .engaged or self.engagement == .alerted;
    }

    /// Check if AI should be updated (not resetting/leashing)
    pub fn shouldUpdateCombat(self: *const AIState) bool {
        return self.engagement == .engaged;
    }

    /// Get effective aggro radius (with default fallback)
    pub fn getAggroRadius(self: *const AIState) f32 {
        return if (self.aggro_radius > 0) self.aggro_radius else Config.AGGRO_RADIUS;
    }

    /// Get effective leash radius (with default fallback)
    pub fn getLeashRadius(self: *const AIState) f32 {
        return if (self.leash_radius > 0) self.leash_radius else Config.LEASH_RADIUS;
    }

    /// Record that a phase trigger has fired
    pub fn markPhaseTriggered(self: *AIState, phase_index: u8) void {
        self.triggered_phases |= (@as(u8, 1) << @intCast(phase_index));
    }

    /// Check if a phase has already triggered
    pub fn hasPhaseTriggered(self: *const AIState, phase_index: u8) bool {
        return (self.triggered_phases & (@as(u8, 1) << @intCast(phase_index))) != 0;
    }
};

// ============================================================================
// WORLD STATE - Combat snapshot for decision making
// ============================================================================

const MAX_ENTITIES: usize = 128;

pub const WorldState = struct {
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

    // Team health totals (for last stand calculation)
    ally_total_health: f32 = 0,
    ally_max_health: f32 = 0,
    enemy_total_health: f32 = 0,
    enemy_max_health: f32 = 0,

    // Positions
    enemy_center: rl.Vector3 = .{ .x = 0, .y = 0, .z = 0 },

    // External systems
    terrain: *const TerrainGrid,
    building_mgr: ?*const BuildingManager,
    vfx_mgr: *VFXManager,
    rng: *std.Random,
    telem: ?*MatchTelemetry,
    dt: f32,

    pub fn build(
        self_char: *Character,
        all_entities: []Character,
        terrain: *const TerrainGrid,
        building_mgr: ?*const BuildingManager,
        vfx_mgr: *VFXManager,
        rng: *std.Random,
        telem: ?*MatchTelemetry,
        dt: f32,
    ) WorldState {
        var state = WorldState{
            .self = self_char,
            .entities = all_entities,
            .terrain = terrain,
            .building_mgr = building_mgr,
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

                    // Track team health totals
                    state.ally_total_health += ent.stats.warmth;
                    state.ally_max_health += ent.stats.max_warmth;

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

                    // Track team health totals
                    state.enemy_total_health += ent.stats.warmth;
                    state.enemy_max_health += ent.stats.max_warmth;

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

    /// Check if AI's team should enter "last stand" mode
    /// Returns true if the fight is clearly lost and fleeing is pointless
    fn shouldLastStand(self: *const WorldState) bool {
        // Condition 1: Heavily outnumbered (2+ more enemies than allies)
        const ally_count_i: i32 = @intCast(self.ally_count);
        const enemy_count_i: i32 = @intCast(self.enemy_count);
        if (enemy_count_i - ally_count_i >= Config.LAST_STAND_OUTNUMBER_THRESHOLD) {
            return true;
        }

        // Condition 2: Team health is much lower than enemy team health
        // (our team has < 30% of enemy team's current health)
        if (self.enemy_total_health > 0) {
            const health_ratio = self.ally_total_health / self.enemy_total_health;
            if (health_ratio < Config.LAST_STAND_HEALTH_RATIO) {
                return true;
            }
        }

        // Condition 3: Last one standing (all allies dead except self)
        if (self.ally_count == 1) {
            return true;
        }

        return false;
    }

    fn hasWallTo(self: *const WorldState, target: *const Character) bool {
        // Check terrain walls (snow walls built by players)
        if (self.terrain.hasWallBetween(
            self.self.position.x,
            self.self.position.z,
            target.position.x,
            target.position.z,
            10.0,
        )) {
            return true;
        }

        // Check building LoS blocking
        if (self.building_mgr) |bm| {
            if (!bm.checkLoS(
                self.self.position.x,
                self.self.position.z,
                target.position.x,
                target.position.z,
            )) {
                return true; // Building blocks LoS
            }
        }

        return false;
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
    /// Considers: speed modifier, ice risk (if enemies nearby), wall obstacles, buildings
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

        // Check for buildings blocking the path
        if (self.building_mgr) |bm| {
            // Sample multiple points along the path for building collision
            const sample_count: usize = 3;
            for (1..sample_count + 1) |i| {
                const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(sample_count));
                const sample_x = self.self.position.x + dir_x * sample_dist * t;
                const sample_z = self.self.position.z + dir_z * sample_dist * t;
                if (bm.checkCollision(sample_x, sample_z) != null) {
                    score -= 1.0; // Heavy penalty - path blocked by building
                    break;
                }
            }
        }

        return score;
    }

    // ========== BUILDING AVOIDANCE HELPERS ==========

    /// Check if there's a clear path to a position (no buildings blocking)
    fn hasClearPathTo(self: *const WorldState, target_x: f32, target_z: f32) bool {
        if (self.building_mgr) |bm| {
            return bm.checkLoS(self.self.position.x, self.self.position.z, target_x, target_z);
        }
        return true; // No buildings = clear path
    }

    /// Check if a specific position is blocked by a building
    fn isBuildingAt(self: *const WorldState, x: f32, z: f32) bool {
        if (self.building_mgr) |bm| {
            return bm.checkCollision(x, z) != null;
        }
        return false;
    }

    /// Find a steering direction to avoid buildings while moving toward a target
    /// Returns adjusted direction (normalized) or original direction if no adjustment needed
    fn findBuildingAvoidanceDir(self: *const WorldState, target_x: f32, target_z: f32, look_ahead: f32) struct { x: f32, z: f32 } {
        const dx = target_x - self.self.position.x;
        const dz = target_z - self.self.position.z;
        const dist = @sqrt(dx * dx + dz * dz);

        if (dist < 1.0) return .{ .x = 0, .z = 0 };

        const dir_x = dx / dist;
        const dir_z = dz / dist;

        // Check if direct path is clear
        const check_dist = @min(look_ahead, dist);
        const check_x = self.self.position.x + dir_x * check_dist;
        const check_z = self.self.position.z + dir_z * check_dist;

        if (!self.isBuildingAt(check_x, check_z)) {
            // Direct path is clear
            return .{ .x = dir_x, .z = dir_z };
        }

        // Direct path blocked - try to steer around
        // Check perpendicular directions (left and right)
        const perp_l_x = -dir_z;
        const perp_l_z = dir_x;
        const perp_r_x = dir_z;
        const perp_r_z = -dir_x;

        // Sample several angles to find a clear path
        const angles = [_]f32{ 0.3, 0.5, 0.7, 0.9 }; // Blend amounts toward perpendicular

        var best_dir_x: f32 = dir_x;
        var best_dir_z: f32 = dir_z;
        var found_clear = false;

        // Try left side first
        for (angles) |blend| {
            const try_x = dir_x * (1.0 - blend) + perp_l_x * blend;
            const try_z = dir_z * (1.0 - blend) + perp_l_z * blend;
            const try_dist = @sqrt(try_x * try_x + try_z * try_z);
            const norm_x = try_x / try_dist;
            const norm_z = try_z / try_dist;

            const sample_x = self.self.position.x + norm_x * check_dist;
            const sample_z = self.self.position.z + norm_z * check_dist;

            if (!self.isBuildingAt(sample_x, sample_z)) {
                best_dir_x = norm_x;
                best_dir_z = norm_z;
                found_clear = true;
                break;
            }
        }

        // If left didn't work, try right
        if (!found_clear) {
            for (angles) |blend| {
                const try_x = dir_x * (1.0 - blend) + perp_r_x * blend;
                const try_z = dir_z * (1.0 - blend) + perp_r_z * blend;
                const try_dist = @sqrt(try_x * try_x + try_z * try_z);
                const norm_x = try_x / try_dist;
                const norm_z = try_z / try_dist;

                const sample_x = self.self.position.x + norm_x * check_dist;
                const sample_z = self.self.position.z + norm_z * check_dist;

                if (!self.isBuildingAt(sample_x, sample_z)) {
                    best_dir_x = norm_x;
                    best_dir_z = norm_z;
                    break;
                }
            }
        }

        return .{ .x = best_dir_x, .z = best_dir_z };
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

/// Update AI's facing angle to face their current target
/// This is important so movement penalties (backpedal/strafe) apply correctly
fn updateFacingAngle(self: *Character, world: *const WorldState) void {
    // Face the nearest enemy if there is one
    if (world.nearest_enemy) |enemy| {
        const dx = enemy.position.x - self.position.x;
        const dz = enemy.position.z - self.position.z;
        const dist = @sqrt(dx * dx + dz * dz);
        if (dist > 1.0) {
            self.facing_angle = std.math.atan2(dz, dx);
        }
    }
}

fn calcMovement(world: *WorldState, ai: *AIState, action: ?*const SkillAction, is_player_ally: bool) MovementIntent {
    const self = world.self;
    var move_x: f32 = 0.0;
    var move_z: f32 = 0.0;

    // Update facing angle to face enemy - critical for movement penalties to work correctly
    updateFacingAngle(self, world);

    // Ally backline (healers) should NOT chase targets - they hold position and let allies come to them
    // Otherwise they run away from combat trying to chase fleeing allies
    const is_ally_backline = is_player_ally and ai.formation == .backline;

    // Priority: Move toward queued skill target (but not for ally backline)
    if (self.hasQueuedSkill() and !is_ally_backline) {
        if (self.casting.queued_skill) |queued| {
            for (world.entities) |*e| {
                if (e.id == queued.target_id and e.isAlive()) {
                    // Use building avoidance when moving to target
                    const avoid_dir = world.findBuildingAvoidanceDir(e.position.x, e.position.z, 60.0);
                    move_x = avoid_dir.x;
                    move_z = avoid_dir.z;
                    break;
                }
            }
        }
    }
    // Otherwise: Move toward chosen action target if out of range (but not for ally backline with ally targets)
    else if (action) |a| {
        if (!a.in_range) {
            if (a.target) |target| {
                // Ally backline should not chase ally targets (would run away from fight)
                // They CAN chase enemy targets (offensive skills)
                const is_ally_target = self.isAlly(target.*);
                if (!is_ally_backline or !is_ally_target) {
                    // Use building avoidance when moving to target
                    const avoid_dir = world.findBuildingAvoidanceDir(target.position.x, target.position.z, 60.0);
                    move_x = avoid_dir.x;
                    move_z = avoid_dir.z;
                }
            }
        }
    }

    // Tactical positioning when no specific target (or ally backline holding position)
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

                // ========== LAST STAND CHECK ==========
                // If the fight is hopeless, stop running and fight to the death
                // Also triggers after kiting for too long (prevents endless chases)
                if (!ai.last_stand) {
                    // Check situational triggers
                    if (world.shouldLastStand()) {
                        ai.last_stand = true;
                    }
                    // Check kite time trigger
                    if (ai.kite_time_ms >= Config.MAX_KITE_TIME_MS) {
                        ai.last_stand = true;
                    }
                }

                // Update kite timer
                if (ai.is_kiting) {
                    ai.kite_time_ms +|= @intFromFloat(world.dt * 1000.0);
                } else {
                    // Reset kite timer when not kiting
                    ai.kite_time_ms = 0;
                }

                // In last stand mode, always advance toward the enemy
                if (ai.last_stand) {
                    ai.is_kiting = false;
                    if (dist > preferred * 0.5) {
                        // Advance aggressively (with building avoidance)
                        const avoid_dir = world.findBuildingAvoidanceDir(enemy.position.x, enemy.position.z, 60.0);
                        move_x = avoid_dir.x;
                        move_z = avoid_dir.z;
                    }
                    // If close enough, hold position and fight
                } else {
                    // Normal tactical behavior based on formation
                    switch (ai.formation) {
                        .frontline => {
                            if (dist > preferred * 1.2) {
                                // Advance (with building avoidance)
                                const avoid_dir = world.findBuildingAvoidanceDir(enemy.position.x, enemy.position.z, 60.0);
                                move_x = avoid_dir.x;
                                move_z = avoid_dir.z;
                            }
                        },
                        .midline => {
                            // Kite when hurt (but not in last stand)
                            if (self_hp < Config.LOW_HEALTH or (dist < Config.MELEE_RANGE and self_hp < Config.WOUNDED)) {
                                // Retreating - check if retreat direction hits a building
                                const retreat_x = self.position.x - dir_x * 60.0;
                                const retreat_z = self.position.z - dir_z * 60.0;
                                if (!world.isBuildingAt(retreat_x, retreat_z)) {
                                    move_x = -dir_x;
                                    move_z = -dir_z;
                                } else {
                                    // Building behind us - try to strafe instead
                                    const perp_x = -dir_z;
                                    const perp_z = dir_x;
                                    const strafe_x = self.position.x + perp_x * 60.0;
                                    const strafe_z = self.position.z + perp_z * 60.0;
                                    if (!world.isBuildingAt(strafe_x, strafe_z)) {
                                        move_x = perp_x;
                                        move_z = perp_z;
                                    } else {
                                        // Try other strafe direction
                                        move_x = -perp_x;
                                        move_z = -perp_z;
                                    }
                                }
                                ai.is_kiting = true;
                            } else if (dist > preferred * 1.5) {
                                // Very far - full speed approach (with building avoidance)
                                const avoid_dir = world.findBuildingAvoidanceDir(enemy.position.x, enemy.position.z, 60.0);
                                move_x = avoid_dir.x;
                                move_z = avoid_dir.z;
                                ai.is_kiting = false;
                            } else if (dist > preferred * 1.1) {
                                // Slightly out of range - approach at reduced speed (with building avoidance)
                                const avoid_dir = world.findBuildingAvoidanceDir(enemy.position.x, enemy.position.z, 40.0);
                                move_x = avoid_dir.x * 0.7;
                                move_z = avoid_dir.z * 0.7;
                                ai.is_kiting = false;
                            } else if (dist < preferred * 0.7) {
                                move_x = -dir_x * 0.5;
                                move_z = -dir_z * 0.5;
                            } else {
                                ai.is_kiting = false;
                            }
                        },
                        .backline => {
                            // Ally backline (healers on player team): stay near allies, don't kite away
                            // They should maintain healing range but not run away scared
                            if (is_player_ally) {
                                // Ally healer behavior: stay at preferred range, approach if too far
                                if (dist > preferred * 1.2) {
                                    // Too far - approach to get in healing range (with building avoidance)
                                    const avoid_dir = world.findBuildingAvoidanceDir(enemy.position.x, enemy.position.z, 40.0);
                                    move_x = avoid_dir.x * 0.6;
                                    move_z = avoid_dir.z * 0.6;
                                    ai.is_kiting = false;
                                } else if (dist < preferred * 0.5) {
                                    // Too close - back up slightly but don't flee
                                    move_x = -dir_x * 0.3;
                                    move_z = -dir_z * 0.3;
                                    ai.is_kiting = false; // Not really kiting, just repositioning
                                } else {
                                    // Good range - hold position
                                    ai.is_kiting = false;
                                }
                            } else {
                                // Enemy backline behavior: retreat when threatened (original behavior)
                                if (dist < Config.THREAT_RANGE) {
                                    // Retreating - check if retreat direction hits a building
                                    const retreat_x = self.position.x - dir_x * 60.0;
                                    const retreat_z = self.position.z - dir_z * 60.0;
                                    if (!world.isBuildingAt(retreat_x, retreat_z)) {
                                        move_x = -dir_x;
                                        move_z = -dir_z;
                                    } else {
                                        // Building behind us - strafe instead
                                        move_x = -dir_z;
                                        move_z = dir_x;
                                    }
                                    ai.is_kiting = true;
                                } else if (dist < Config.BACKLINE_SAFE_DIST) {
                                    move_x = -dir_x * 0.5;
                                    move_z = -dir_z * 0.5;
                                    ai.is_kiting = true;
                                } else if (dist > preferred * 1.5) {
                                    // Too far from fight - cautiously approach (with building avoidance)
                                    const avoid_dir = world.findBuildingAvoidanceDir(enemy.position.x, enemy.position.z, 40.0);
                                    move_x = avoid_dir.x * 0.5;
                                    move_z = avoid_dir.z * 0.5;
                                    ai.is_kiting = false;
                                } else {
                                    ai.is_kiting = false;
                                }
                            }
                        },
                    }
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

    // Convert world-space movement to local-space for MovementIntent
    // This is the INVERSE of the rotation in applyMovement
    // applyMovement does: world = [cos θ, sin θ; -sin θ, cos θ] * local
    // So we need: local = [cos θ, -sin θ; sin θ, cos θ] * world
    const cos_f = @cos(self.facing_angle);
    const sin_f = @sin(self.facing_angle);

    const result = MovementIntent{
        .local_x = move_x * cos_f - move_z * sin_f,
        .local_z = move_x * sin_f + move_z * cos_f,
        .facing_angle = self.facing_angle,
        .apply_penalties = true,
    };

    return result;
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
// ENGAGEMENT STATE MACHINE
// ============================================================================
// Handles aggro, leashing, and reset behavior for dungeon/encounter AI.
// Standard arena AI (no spawn_position set) skips this and always fights.

/// Update engagement state for a single AI entity
/// Returns true if the AI should proceed with combat logic, false if idle/leashing/resetting
pub fn updateEngagementState(
    ent: *Character,
    ai: *AIState,
    world: *const WorldState,
    delta_time_ms: u32,
) bool {
    // Skip engagement logic if no spawn position set (standard arena AI)
    if (ai.spawn_position == null) {
        ai.engagement = .engaged;
        return true;
    }

    const spawn_pos = ai.spawn_position.?;

    switch (ai.engagement) {
        .idle => {
            // Check if any enemy is within aggro radius
            if (world.nearest_enemy) |_| {
                if (world.nearest_enemy_dist <= ai.getAggroRadius()) {
                    // Player entered aggro range - transition to alerted
                    ai.engagement = .alerted;
                    ai.engagement_timer_ms = 0;
                    ai.aggro_source_id = if (world.nearest_enemy) |e| e.id else null;
                    ai.was_pulled = true;
                }
            }
            return false; // Don't run combat AI while idle
        },

        .alerted => {
            // Brief alert phase before engaging (dramatic pause)
            ai.engagement_timer_ms += delta_time_ms;

            if (ai.engagement_timer_ms >= Config.ALERT_DURATION_MS) {
                // Finished alert animation - engage!
                ai.engagement = .engaged;
                ai.combat_time_ms = 0;
            }
            return false; // Don't run combat AI during alert
        },

        .engaged => {
            // Track combat time (for phase triggers)
            ai.combat_time_ms += delta_time_ms;

            // Check if should leash (all enemies too far)
            if (world.nearest_enemy) |_| {
                const dist_to_spawn = distanceXZ(ent.position, spawn_pos);

                if (dist_to_spawn > ai.getLeashRadius()) {
                    // Too far from spawn - start leashing
                    ai.engagement = .leashing;
                    ent.stopAutoAttack();
                }
            } else {
                // No enemies visible - could leash or enemies all dead
                // For now, stay engaged (victory condition handles this)
            }
            return true; // Run combat AI
        },

        .leashing => {
            // Move back toward spawn position
            const dist_to_spawn = distanceXZ(ent.position, spawn_pos);

            if (dist_to_spawn < 20.0) {
                // Reached spawn - start resetting
                ai.engagement = .resetting;
                ai.engagement_timer_ms = 0;
                ent.stopAutoAttack();
            }
            return false; // Don't run combat AI while leashing
        },

        .resetting => {
            // Wait at spawn before fully resetting
            ai.engagement_timer_ms += delta_time_ms;

            if (ai.engagement_timer_ms >= Config.RESET_DELAY_MS) {
                // Reset complete - heal to full and return to idle
                ent.stats.warmth = ent.stats.max_warmth;
                ent.stats.energy = ent.stats.max_energy;

                // Clear all conditions (chills, cozies, effects)
                ent.conditions.clearAll();

                // Reset phase tracking (for bosses)
                ai.current_phase = 0;
                ai.triggered_phases = 0;
                ai.combat_time_ms = 0;
                ai.adds_killed = 0;

                ai.engagement = .idle;
            }
            return false; // Don't run combat AI while resetting
        },
    }
}

/// Calculate movement for leashing AI (returning to spawn)
pub fn calcLeashMovement(ent: *const Character, ai_state: *const AIState) MovementIntent {
    const spawn_pos = ai_state.spawn_position orelse return .{
        .local_x = 0,
        .local_z = 0,
        .facing_angle = ent.facing_angle,
        .apply_penalties = true,
    };

    const dx = spawn_pos.x - ent.position.x;
    const dz = spawn_pos.z - ent.position.z;
    const dist = @sqrt(dx * dx + dz * dz);

    if (dist < 1.0) {
        return .{
            .local_x = 0,
            .local_z = 0,
            .facing_angle = ent.facing_angle,
            .apply_penalties = true,
        };
    }

    // Move toward spawn at increased speed
    const move_x = (dx / dist) * Config.LEASH_SPEED_MULTIPLIER;
    const move_z = (dz / dist) * Config.LEASH_SPEED_MULTIPLIER;

    // Convert to local space
    const cos_f = @cos(ent.facing_angle);
    const sin_f = @sin(ent.facing_angle);

    return .{
        .local_x = move_x * cos_f + move_z * sin_f,
        .local_z = -move_x * sin_f + move_z * cos_f,
        .facing_angle = ent.facing_angle,
        .apply_penalties = false, // No terrain penalties when leashing
    };
}

/// Helper: distance in XZ plane (ignoring Y)
fn distanceXZ(a: rl.Vector3, b: rl.Vector3) f32 {
    const dx = a.x - b.x;
    const dz = a.z - b.z;
    return @sqrt(dx * dx + dz * dz);
}

// ============================================================================
// BOSS PHASE SYSTEM
// ============================================================================
// Checks phase triggers and applies phase transitions for boss AI.
// Phase triggers are checked every tick while boss is engaged.
// Phase transitions can:
// - Override the boss's skill bar
// - Spawn adds
// - Modify arena (terrain/hazards)
// - Change boss stats (damage/speed multipliers)

const encounter = @import("encounter.zig");
const BossConfig = encounter.BossConfig;
const BossPhase = encounter.BossPhase;
const PhaseTrigger = encounter.PhaseTrigger;

/// Result of checking boss phases
pub const PhaseCheckResult = struct {
    /// Did a new phase trigger?
    phase_triggered: bool = false,
    /// Index of the triggered phase
    triggered_phase_index: u8 = 0,
    /// The triggered phase (if any)
    triggered_phase: ?*const BossPhase = null,
};

/// Check if any boss phases should trigger
/// Call this every tick for boss AI entities
pub fn checkBossPhases(
    ent: *const Character,
    ai: *AIState,
    boss_config: *const BossConfig,
) PhaseCheckResult {
    var result = PhaseCheckResult{};

    const current_warmth_percent = ent.stats.warmth / ent.stats.max_warmth;

    for (boss_config.phases, 0..) |*phase, phase_idx| {
        const idx: u8 = @intCast(phase_idx);

        // Skip already triggered phases
        if (ai.hasPhaseTriggered(idx)) continue;

        // Check if this phase should trigger
        const should_trigger = switch (phase.trigger) {
            .warmth_percent => |threshold| current_warmth_percent <= threshold,
            .time_in_combat_ms => |time| ai.combat_time_ms >= time,
            .adds_killed => |count| ai.adds_killed >= count,
            .skill_interrupted => false, // Handled elsewhere via interrupt callback
            .combat_start => ai.combat_time_ms == 0, // Only on first tick of combat
            .manual => false, // Triggered externally
        };

        if (should_trigger) {
            ai.markPhaseTriggered(idx);
            ai.current_phase = idx;

            result.phase_triggered = true;
            result.triggered_phase_index = idx;
            result.triggered_phase = phase;

            // Only trigger one phase per tick
            break;
        }
    }

    return result;
}

/// Apply a boss phase transition to a character
/// This updates skills, stats, and returns info about adds to spawn
pub fn applyBossPhase(
    ent: *Character,
    phase: *const BossPhase,
) void {
    // Apply skill bar override
    if (phase.skill_bar_override) |skill_bar| {
        for (skill_bar, 0..) |maybe_skill, slot| {
            ent.casting.skills[slot] = maybe_skill;
        }
    }

    // Note: Arena changes and add spawning need to be handled by the game state
    // since they affect the world, not just this character.
    // The caller should check phase.arena_changes and phase.add_spawn

    // Stat multipliers are typically handled by the combat system reading from
    // the current phase. For now, we could store the multipliers on the AI state
    // or apply them directly. Let's log for debugging.
    if (phase.phase_name) |name| {
        std.debug.print("=== BOSS PHASE: {s} ===\n", .{name});
    }
    if (phase.boss_yell) |yell| {
        std.debug.print("Boss: \"{s}\"\n", .{yell});
    }
}

/// Get the current phase's damage multiplier for a boss
pub fn getBossPhaseMultiplier(
    ai: *const AIState,
    boss_config: *const BossConfig,
) struct { damage: f32, speed: f32 } {
    if (ai.current_phase < boss_config.phases.len) {
        const phase = &boss_config.phases[ai.current_phase];
        return .{
            .damage = phase.damage_multiplier,
            .speed = phase.speed_multiplier,
        };
    }
    return .{ .damage = 1.0, .speed = 1.0 };
}

// ============================================================================
// PATROL BEHAVIOR
// ============================================================================
// Movement for idle AI following patrol paths.

/// Calculate movement for patrolling AI
/// Returns movement intent to follow patrol path
pub fn calcPatrolMovement(
    ent: *const Character,
    patrol_path: []const rl.Vector3,
    current_waypoint: *usize,
    patrol_speed: f32,
) MovementIntent {
    if (patrol_path.len == 0) {
        return .{
            .local_x = 0,
            .local_z = 0,
            .facing_angle = ent.facing_angle,
            .apply_penalties = true,
        };
    }

    // Get current target waypoint
    const target = patrol_path[current_waypoint.*];

    // Check if reached waypoint
    const dist = distanceXZ(ent.position, target);
    if (dist < 20.0) {
        // Move to next waypoint (loop around)
        current_waypoint.* = (current_waypoint.* + 1) % patrol_path.len;
    }

    // Calculate direction to waypoint
    const dx = target.x - ent.position.x;
    const dz = target.z - ent.position.z;

    if (dist < 1.0) {
        return .{
            .local_x = 0,
            .local_z = 0,
            .facing_angle = ent.facing_angle,
            .apply_penalties = true,
        };
    }

    const move_x = (dx / dist) * patrol_speed;
    const move_z = (dz / dist) * patrol_speed;

    // Convert to local space
    const cos_f = @cos(ent.facing_angle);
    const sin_f = @sin(ent.facing_angle);

    return .{
        .local_x = move_x * cos_f + move_z * sin_f,
        .local_z = -move_x * sin_f + move_z * cos_f,
        .facing_angle = ent.facing_angle,
        .apply_penalties = true,
    };
}

// ============================================================================
// HAZARD ZONE PROCESSING
// ============================================================================
// Runtime processing for hazard zones defined in encounters.
// Hazards deal damage, apply effects, or knockback characters inside them.

const HazardZone = encounter.HazardZone;
const HazardType = encounter.HazardType;
const HazardShape = encounter.HazardShape;

/// State for tracking active hazard zones in an encounter
pub const HazardZoneState = struct {
    zone: *const HazardZone,
    time_remaining_ms: u32,
    tick_timer_ms: u32 = 0,
    warning_complete: bool = false,

    pub fn init(zone: *const HazardZone) HazardZoneState {
        return .{
            .zone = zone,
            .time_remaining_ms = if (zone.duration_ms > 0) zone.duration_ms else std.math.maxInt(u32),
            .warning_complete = zone.warning_time_ms == 0,
        };
    }

    /// Update the hazard zone, returns true if zone should be removed
    pub fn update(self: *HazardZoneState, delta_time_ms: u32) bool {
        // Handle warning phase
        if (!self.warning_complete) {
            if (self.tick_timer_ms >= self.zone.warning_time_ms) {
                self.warning_complete = true;
                self.tick_timer_ms = 0;
            } else {
                self.tick_timer_ms += delta_time_ms;
                return false;
            }
        }

        // Update duration
        if (self.time_remaining_ms != std.math.maxInt(u32)) {
            if (delta_time_ms >= self.time_remaining_ms) {
                return true; // Zone expired
            }
            self.time_remaining_ms -= delta_time_ms;
        }

        // Update tick timer
        self.tick_timer_ms += delta_time_ms;

        return false;
    }

    /// Check if hazard should tick damage this frame
    pub fn shouldTick(self: *HazardZoneState) bool {
        if (!self.warning_complete) return false;
        if (self.tick_timer_ms >= self.zone.tick_rate_ms) {
            self.tick_timer_ms = 0;
            return true;
        }
        return false;
    }
};

/// Check if a position is inside a hazard zone
pub fn isInsideHazard(pos: rl.Vector3, zone: *const HazardZone) bool {
    const dx = pos.x - zone.center.x;
    const dz = pos.z - zone.center.z;
    const dist = @sqrt(dx * dx + dz * dz);

    return switch (zone.shape) {
        .circle => dist <= zone.radius,
        .ring => dist <= zone.radius and dist >= zone.radius * 0.5, // Inner radius = 50% of outer
        .cone, .line, .moving_line => {
            // Simplified: treat as circle for now
            return dist <= zone.radius;
        },
    };
}

/// Apply hazard effects to a character
/// Returns damage dealt (for telemetry/feedback)
pub fn applyHazardEffect(
    ent: *Character,
    zone: *const HazardZone,
) f32 {
    var damage_dealt: f32 = 0.0;

    switch (zone.hazard_type) {
        .damage => {
            damage_dealt = zone.damage_per_tick;
            ent.stats.warmth = @max(0, ent.stats.warmth - damage_dealt);
        },
        .slow => {
            // Apply slippery chill (movement slow)
            _ = ent.conditions.addChill(.{
                .chill = .slippery,
                .duration_ms = zone.tick_rate_ms + 100, // Slightly longer than tick rate
                .stack_intensity = 1,
            }, null);
        },
        .knockback => {
            // Push character away from center
            const dx = ent.position.x - zone.center.x;
            const dz = ent.position.z - zone.center.z;
            const dist = @sqrt(dx * dx + dz * dz);
            if (dist > 0.1) {
                const push_strength: f32 = 50.0;
                ent.position.x += (dx / dist) * push_strength;
                ent.position.z += (dz / dist) * push_strength;
            }
        },
        .knockdown => {
            // Apply knocked_down chill
            _ = ent.conditions.addChill(.{
                .chill = .knocked_down,
                .duration_ms = 2000,
                .stack_intensity = 1,
            }, null);
        },
        .freeze => {
            // Apply frost_eyes (blind) and slippery
            _ = ent.conditions.addChill(.{
                .chill = .frost_eyes,
                .duration_ms = 3000,
                .stack_intensity = 1,
            }, null);
            _ = ent.conditions.addChill(.{
                .chill = .slippery,
                .duration_ms = 3000,
                .stack_intensity = 2,
            }, null);
        },
        .blind => {
            _ = ent.conditions.addChill(.{
                .chill = .frost_eyes,
                .duration_ms = zone.tick_rate_ms + 100,
                .stack_intensity = 1,
            }, null);
        },
        .pull => {
            // Pull character toward center
            const dx = zone.center.x - ent.position.x;
            const dz = zone.center.z - ent.position.z;
            const dist = @sqrt(dx * dx + dz * dz);
            if (dist > 10.0) {
                const pull_strength: f32 = 30.0;
                ent.position.x += (dx / dist) * pull_strength;
                ent.position.z += (dz / dist) * pull_strength;
            }
        },
        .safe_zone => {
            // Safe zones don't do anything to characters inside
            // Damage is applied to those OUTSIDE (handled by caller inverting the check)
        },
    }

    return damage_dealt;
}

/// Process all hazard zones for all entities
/// Call this once per tick from game state
pub fn processHazardZones(
    entities: []Character,
    hazard_states: []HazardZoneState,
    delta_time_ms: u32,
) void {
    for (hazard_states) |*state| {
        // Update the hazard zone timer
        const expired = state.update(delta_time_ms);
        if (expired) continue; // Will be cleaned up by caller

        // Check if should apply effects this tick
        if (!state.shouldTick()) continue;

        const zone = state.zone;

        // Check each entity
        for (entities) |*ent| {
            if (!ent.isAlive()) continue;

            // Check team filtering
            const is_player_team = ent.team == .blue; // Assuming blue = player team
            if (is_player_team and !zone.affects_players) continue;
            if (!is_player_team and !zone.affects_enemies) continue;

            // Check if inside hazard
            var should_apply = isInsideHazard(ent.position, zone);

            // Invert for safe zones (damage outside, safe inside)
            if (zone.hazard_type == .safe_zone) {
                should_apply = !should_apply;
            }

            if (should_apply) {
                _ = applyHazardEffect(ent, zone);
            }
        }
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
    building_manager: ?*const BuildingManager,
) void {
    // Increment global tick counter each update (works for both real-time and headless)
    ai_global_tick +%= 1;

    // Convert delta_time to ms for engagement timers
    const delta_time_ms: u32 = @intFromFloat(delta_time * 1000.0);

    // Find the player's team for ally AI behavior
    var player_team: ?entity_types.Team = null;
    for (entities) |*ent| {
        if (ent.id == controlled_entity_id) {
            player_team = ent.team;
            break;
        }
    }

    for (entities, 0..) |*ent, i| {
        if (!ent.isAlive()) continue;
        if (ent.id == controlled_entity_id) continue;
        if (i >= ai_states.len) continue;

        var ai = &ai_states[i];

        // Check if this AI is on the player's team (ally AI)
        const is_player_ally = if (player_team) |pt| ent.team == pt else false;

        // Initialize if needed
        if (ai.role == .damage_dealer and ai.formation == .midline and ent.player_position != .pitcher and ent.player_position != .fielder) {
            ai.* = AIState.init(ent.player_position);
        }

        // Build world state
        var world = WorldState.build(ent, entities, terrain_grid, building_manager, vfx_manager, rng, match_telemetry, delta_time);

        // ========== ENGAGEMENT STATE MACHINE ==========
        // Check aggro, leashing, and reset states for dungeon AI
        const should_combat = updateEngagementState(ent, ai, &world, delta_time_ms);

        // Handle leashing movement (return to spawn)
        if (ai.engagement == .leashing) {
            const intent = calcLeashMovement(ent, ai);
            movement.applyMovement(ent, intent, entities, null, null, delta_time, terrain_grid, building_manager);
            continue; // Skip combat logic
        }

        // Skip combat AI if not engaged
        if (!should_combat) {
            continue;
        }

        // ========== COMBAT AI (only when engaged) ==========

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
            const intent = calcMovement(&world, ai, if (chosen_action) |*a| a else null, is_player_ally);
            movement.applyMovement(ent, intent, entities, null, null, delta_time, terrain_grid, building_manager);
        }
    }
}

// ============================================================================
// SOCIAL AGGRO / LINK PULLING
// ============================================================================

/// Pull linked waves when a wave is engaged
/// Call this when an AI transitions from idle to alerted/engaged
pub fn pullLinkedWaves(
    pulled_wave_index: u8,
    wave_link_groups: []const []const u8,
    ai_states: []AIState,
    aggro_source_id: EntityId,
) void {
    if (pulled_wave_index >= wave_link_groups.len) return;

    const linked_waves = wave_link_groups[pulled_wave_index];

    for (ai_states) |*ai| {
        // Check if this AI is in a linked wave
        for (linked_waves) |linked_idx| {
            if (ai.wave_index == linked_idx and ai.engagement == .idle) {
                // Pull this AI
                ai.engagement = .alerted;
                ai.engagement_timer_ms = 0;
                ai.aggro_source_id = aggro_source_id;
                ai.was_pulled = true;
            }
        }
    }
}

/// Check for social aggro (nearby allies pull each other)
pub fn checkSocialAggro(
    ai_states: []AIState,
    entities: []const Character,
    aggro_source_id: EntityId,
) void {
    // Find all engaged AI and pull nearby idle AI
    for (ai_states, 0..) |*ai, i| {
        if (ai.engagement != .engaged) continue;
        if (i >= entities.len) continue;

        const engaged_pos = entities[i].position;

        // Check nearby AI for social aggro
        for (ai_states, 0..) |*other_ai, j| {
            if (other_ai.engagement != .idle) continue;
            if (j >= entities.len) continue;
            if (entities[i].team != entities[j].team) continue; // Only same team

            const other_pos = entities[j].position;
            const dist = distanceXZ(engaged_pos, other_pos);

            if (dist <= Config.SOCIAL_AGGRO_RADIUS) {
                // Pull this AI via social aggro
                other_ai.engagement = .alerted;
                other_ai.engagement_timer_ms = 0;
                other_ai.aggro_source_id = aggro_source_id;
                other_ai.was_pulled = true;
            }
        }
    }
}
