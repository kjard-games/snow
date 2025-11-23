const std = @import("std");
const rl = @import("raylib");
const character = @import("character.zig");
const targeting = @import("targeting.zig");
const combat = @import("combat.zig");
const game_state = @import("game_state.zig");
const skills = @import("skills.zig");
const movement = @import("movement.zig");
const entity_types = @import("entity.zig");
const position = @import("position.zig");

const Character = character.Character;
const Skill = character.Skill;
const MovementIntent = movement.MovementIntent;
const EntityId = entity_types.EntityId;
const Position = position.Position;
const print = std.debug.print;

// ============================================================================
// AI CONFIGURATION CONSTANTS
// ============================================================================

/// Formation positioning thresholds (in game units)
pub const FORMATION = struct {
    pub const FRONTLINE_RANGE: f32 = 200.0; // Distance from enemy center to be considered frontline
    pub const SAFE_DISTANCE: f32 = 180.0; // Safe distance for backline from enemy center
    pub const DANGER_DISTANCE: f32 = 120.0; // Backline retreat threshold
    pub const SPREAD_RADIUS: f32 = 40.0; // Begin spreading when ally is this close
    pub const COMFORT_ZONE: f32 = 20.0; // Range tolerance for positioning
};

/// Threat detection thresholds
pub const THREAT = struct {
    pub const CLOSE_RANGE: f32 = 150.0; // Enemy within this range is threatening
};

/// Healing priorities
pub const HEALING = struct {
    pub const CRITICAL_THRESHOLD: f32 = 0.4; // Below 40% health = critical
    pub const LOW_THRESHOLD: f32 = 0.6; // Below 60% health = needs healing
};

// ============================================================================
// BEHAVIOR TREE STRUCTURE
// ============================================================================

// Behavior tree node status
pub const NodeStatus = enum {
    success,
    failure,
    running,
};

// Context passed to all behavior tree nodes
pub const BehaviorContext = struct {
    self: *Character,
    all_entities: []Character,
    ai_state: *AIState,
    delta_time: f32,
    rng: *std.Random,
    vfx_manager: *@import("vfx.zig").VFXManager,
    terrain_grid: *const @import("terrain.zig").TerrainGrid,

    // Cached context data (filled by root node)
    target: ?*Character = null,
    target_id: ?EntityId = null,
    allies: [8]*Character = undefined,
    allies_count: usize = 0,
    enemies: [8]*Character = undefined,
    enemies_count: usize = 0,

    // Formation data
    formation_anchors: FormationAnchors = undefined,
};

// Base behavior tree node function pointer
pub const BehaviorNodeFn = *const fn (ctx: *BehaviorContext) NodeStatus;

// ============================================================================
// FORMATION CALCULATIONS
// ============================================================================

// Calculate team formation anchors (center, front, back)
pub const FormationAnchors = struct {
    team_center: rl.Vector3,
    ally_frontline_center: rl.Vector3,
    ally_backline_center: rl.Vector3,
    enemy_center: rl.Vector3,
};

fn calculateFormationAnchors(allies: []*Character, enemies: []*Character, allies_count: usize, enemies_count: usize) FormationAnchors {
    var anchors = FormationAnchors{
        .team_center = .{ .x = 0, .y = 0, .z = 0 },
        .ally_frontline_center = .{ .x = 0, .y = 0, .z = 0 },
        .ally_backline_center = .{ .x = 0, .y = 0, .z = 0 },
        .enemy_center = .{ .x = 0, .y = 0, .z = 0 },
    };

    if (allies_count == 0 or enemies_count == 0) return anchors;

    // Calculate team center (all allies)
    for (allies[0..allies_count]) |ally| {
        anchors.team_center.x += ally.position.x;
        anchors.team_center.z += ally.position.z;
    }
    anchors.team_center.x /= @as(f32, @floatFromInt(allies_count));
    anchors.team_center.z /= @as(f32, @floatFromInt(allies_count));

    // Calculate enemy center
    for (enemies[0..enemies_count]) |enemy| {
        anchors.enemy_center.x += enemy.position.x;
        anchors.enemy_center.z += enemy.position.z;
    }
    anchors.enemy_center.x /= @as(f32, @floatFromInt(enemies_count));
    anchors.enemy_center.z /= @as(f32, @floatFromInt(enemies_count));

    // Calculate frontline center (allies closest to enemy)
    var frontline_count: usize = 0;
    for (allies[0..allies_count]) |ally| {
        const dist_to_enemy = @sqrt((ally.position.x - anchors.enemy_center.x) * (ally.position.x - anchors.enemy_center.x) +
            (ally.position.z - anchors.enemy_center.z) * (ally.position.z - anchors.enemy_center.z));

        // Frontline = within formation range of enemy center
        if (dist_to_enemy < FORMATION.FRONTLINE_RANGE) {
            anchors.ally_frontline_center.x += ally.position.x;
            anchors.ally_frontline_center.z += ally.position.z;
            frontline_count += 1;
        }
    }

    if (frontline_count > 0) {
        anchors.ally_frontline_center.x /= @as(f32, @floatFromInt(frontline_count));
        anchors.ally_frontline_center.z /= @as(f32, @floatFromInt(frontline_count));
    } else {
        // No frontline yet, use team center
        anchors.ally_frontline_center = anchors.team_center;
    }

    // Calculate backline center (allies furthest from enemy)
    var backline_count: usize = 0;
    for (allies[0..allies_count]) |ally| {
        const dist_to_enemy = @sqrt((ally.position.x - anchors.enemy_center.x) * (ally.position.x - anchors.enemy_center.x) +
            (ally.position.z - anchors.enemy_center.z) * (ally.position.z - anchors.enemy_center.z));

        // Backline = beyond formation range from enemy center
        if (dist_to_enemy >= FORMATION.FRONTLINE_RANGE) {
            anchors.ally_backline_center.x += ally.position.x;
            anchors.ally_backline_center.z += ally.position.z;
            backline_count += 1;
        }
    }

    if (backline_count > 0) {
        anchors.ally_backline_center.x /= @as(f32, @floatFromInt(backline_count));
        anchors.ally_backline_center.z /= @as(f32, @floatFromInt(backline_count));
    } else {
        // No backline yet, place behind team center
        const dx = anchors.team_center.x - anchors.enemy_center.x;
        const dz = anchors.team_center.z - anchors.enemy_center.z;
        const dist = @sqrt(dx * dx + dz * dz);
        if (dist > 0.1) {
            anchors.ally_backline_center.x = anchors.team_center.x + (dx / dist) * 50.0;
            anchors.ally_backline_center.z = anchors.team_center.z + (dz / dist) * 50.0;
        } else {
            anchors.ally_backline_center = anchors.team_center;
        }
    }

    return anchors;
}

// Threat assessment - who is being targeted by whom?
pub fn isUnderThreat(self: *const Character, enemies: []const *Character, enemies_count: usize) bool {
    // Check if any enemy is close - basic threat detection
    for (enemies[0..enemies_count]) |enemy| {
        const dist = self.distanceTo(enemy.*);
        if (dist < THREAT.CLOSE_RANGE) return true;
    }
    return false;
}

// Find closest ally in a given formation role
pub fn findClosestAllyInRole(self: *const Character, allies: []const *Character, allies_count: usize, role: FormationRole) ?*Character {
    var closest: ?*Character = null;
    var closest_dist: f32 = std.math.floatMax(f32);

    for (allies[0..allies_count]) |ally| {
        if (ally.id == self.id) continue; // Skip self

        const ally_role = FormationRole.fromPosition(ally.player_position);
        if (ally_role == role) {
            const dist = self.distanceTo(ally.*);
            if (dist < closest_dist) {
                closest_dist = dist;
                closest = ally;
            }
        }
    }

    return closest;
}

// Calculate spreading force to avoid clumping (repulsion from nearby allies)
pub fn calculateSpreadingForce(self: *const Character, allies: []const *Character, allies_count: usize) rl.Vector3 {
    var spread_force = rl.Vector3{ .x = 0, .y = 0, .z = 0 };
    const spread_radius = FORMATION.SPREAD_RADIUS;

    for (allies[0..allies_count]) |ally| {
        if (ally.id == self.id) continue; // Skip self

        const dx = self.position.x - ally.position.x;
        const dz = self.position.z - ally.position.z;
        const dist = @sqrt(dx * dx + dz * dz);

        if (dist < spread_radius and dist > 0.1) {
            // Repulsion force (inversely proportional to distance)
            const force_strength = (spread_radius - dist) / spread_radius;
            spread_force.x += (dx / dist) * force_strength;
            spread_force.z += (dz / dist) * force_strength;
        }
    }

    return spread_force;
}

// Composite Nodes (parent nodes that execute children)
pub fn Selector(comptime children: []const BehaviorNodeFn) BehaviorNodeFn {
    return struct {
        fn execute(ctx: *BehaviorContext) NodeStatus {
            for (children) |child| {
                const status = child(ctx);
                if (status != .failure) {
                    return status; // Return success or running
                }
            }
            return .failure; // All children failed
        }
    }.execute;
}

pub fn Sequence(comptime children: []const BehaviorNodeFn) BehaviorNodeFn {
    return struct {
        fn execute(ctx: *BehaviorContext) NodeStatus {
            for (children) |child| {
                const status = child(ctx);
                if (status != .success) {
                    return status; // Return failure or running
                }
            }
            return .success; // All children succeeded
        }
    }.execute;
}

pub const AIRole = enum {
    damage_dealer, // Focus on dealing damage
    support, // Focus on healing/buffing allies
    disruptor, // Focus on interrupts and debuffs
};

// GW1-style formation roles
pub const FormationRole = enum {
    frontline, // Melee/aggressive, holds the line
    midline, // Ranged damage/control, mobile
    backline, // Healers/support, protected

    // Classify position into formation role (balanced 2-2-2 distribution)
    pub fn fromPosition(pos: Position) FormationRole {
        return switch (pos) {
            .sledder, .shoveler => .frontline, // Close range melee - aggressive skirmisher + tank
            .pitcher, .fielder => .midline, // Ranged damage dealers - pure DPS + generalist
            .animator, .thermos => .backline, // Support/control - summoner + healer
        };
    }
};

pub const AIState = struct {
    next_skill_time: f32 = 0.0,
    skill_cooldown: f32 = 1.5, // seconds between AI skill casts (faster = more dangerous)
    role: AIRole = .damage_dealer,
    formation_role: FormationRole = .midline,
};

// ============================================================================
// BEHAVIOR TREE LEAF NODES (Conditions and Actions)
// ============================================================================

// Conditions (return success/failure, never running)
pub const Conditions = struct {
    // Check if target is in range for any skill
    pub fn targetInRange(ctx: *BehaviorContext) NodeStatus {
        if (ctx.target == null) return .failure;
        const target = ctx.target.?;
        const distance = ctx.self.distanceTo(target.*);

        for (ctx.self.skill_bar) |maybe_skill| {
            if (maybe_skill) |skill| {
                if (distance <= skill.cast_range) return .success;
            }
        }
        return .failure;
    }

    // Check if target is casting (interruptible)
    pub fn targetCasting(ctx: *BehaviorContext) NodeStatus {
        if (ctx.target == null) return .failure;
        return if (ctx.target.?.cast_state == .activating) .success else .failure;
    }

    // Check if any ally needs healing (below healing threshold)
    pub fn allyNeedsHealing(ctx: *BehaviorContext) NodeStatus {
        for (ctx.allies[0..ctx.allies_count]) |ally| {
            const health_pct = ally.warmth / ally.max_warmth;
            if (health_pct < HEALING.LOW_THRESHOLD) return .success;
        }
        return .failure;
    }

    // Check if skill is ready to cast
    pub fn canCastSkill(ctx: *BehaviorContext) NodeStatus {
        return if (ctx.ai_state.next_skill_time <= 0) .success else .failure;
    }

    // Check if self is under threat (low health or being targeted)
    pub fn underThreat(ctx: *BehaviorContext) NodeStatus {
        const health_pct = ctx.self.warmth / ctx.self.max_warmth;
        return if (health_pct < HEALING.CRITICAL_THRESHOLD) .success else .failure;
    }

    // Check if it's a good time to use terrain skill
    pub fn shouldUseTerrainSkill(ctx: *BehaviorContext) NodeStatus {
        // Use terrain skills opportunistically (20% chance when off cooldown)
        const roll = ctx.rng.intRangeAtMost(u32, 0, 100);
        return if (roll < 20) .success else .failure;
    }

    // Check if there's an enemy wall blocking our target
    pub fn enemyWallBlocking(ctx: *BehaviorContext) NodeStatus {
        if (ctx.target == null) return .failure;
        const target = ctx.target.?;

        const has_wall = ctx.terrain_grid.hasWallBetween(
            ctx.self.position.x,
            ctx.self.position.z,
            target.position.x,
            target.position.z,
            10.0,
        );

        return if (has_wall) .success else .failure;
    }

    // Check if we should build a defensive wall (under threat)
    pub fn shouldBuildDefensiveWall(ctx: *BehaviorContext) NodeStatus {
        const health_pct = ctx.self.warmth / ctx.self.max_warmth;
        const under_fire = ctx.self.damage_source_count > 0; // Being hit by enemies

        // Build wall if low health AND under fire
        if (health_pct < 0.5 and under_fire) {
            // 50% chance to prioritize wall
            return if (ctx.rng.boolean()) .success else .failure;
        }

        return .failure;
    }
};

// Helper functions for terrain skill placement
fn findBestAllyClumpLocation(ctx: *BehaviorContext) ?rl.Vector3 {
    // Find center of wounded allies
    var center = rl.Vector3{ .x = 0, .y = 0, .z = 0 };
    var wounded_count: usize = 0;

    for (ctx.allies[0..ctx.allies_count]) |ally| {
        const health_pct = ally.warmth / ally.max_warmth;
        if (health_pct < HEALING.LOW_THRESHOLD) {
            center.x += ally.position.x;
            center.z += ally.position.z;
            wounded_count += 1;
        }
    }

    if (wounded_count > 0) {
        center.x /= @as(f32, @floatFromInt(wounded_count));
        center.z /= @as(f32, @floatFromInt(wounded_count));
        return center;
    }

    // Fallback: place near self
    return ctx.self.position;
}

fn findBestEnemyClumpLocation(ctx: *BehaviorContext) ?rl.Vector3 {
    // Find center of enemy clump (most enemies within radius)
    if (ctx.enemies_count == 0) return null;

    var best_pos = ctx.enemies[0].position;
    var best_count: usize = 0;

    // Check each enemy as potential center
    for (ctx.enemies[0..ctx.enemies_count]) |center_enemy| {
        var nearby_count: usize = 0;

        // Count enemies within AoE radius (80 units)
        for (ctx.enemies[0..ctx.enemies_count]) |other_enemy| {
            const dx = center_enemy.position.x - other_enemy.position.x;
            const dz = center_enemy.position.z - other_enemy.position.z;
            const dist = @sqrt(dx * dx + dz * dz);

            if (dist < 80.0) {
                nearby_count += 1;
            }
        }

        if (nearby_count > best_count) {
            best_count = nearby_count;
            best_pos = center_enemy.position;
        }
    }

    return best_pos;
}

fn findBestUtilityTerrainLocation(ctx: *BehaviorContext) ?rl.Vector3 {
    // Place terrain between self and enemy center for tactical advantage
    if (ctx.enemies_count == 0) return ctx.self.position;

    const enemy_center = ctx.formation_anchors.enemy_center;

    // Place 60% of the way toward enemies (creates buffer zone)
    const dx = enemy_center.x - ctx.self.position.x;
    const dz = enemy_center.z - ctx.self.position.z;

    return rl.Vector3{
        .x = ctx.self.position.x + dx * 0.6,
        .y = 0,
        .z = ctx.self.position.z + dz * 0.6,
    };
}

fn findBestDefensiveWallPosition(ctx: *BehaviorContext) rl.Vector3 {
    // Place wall between self and nearest enemy
    if (ctx.enemies_count == 0) {
        // No enemies, place wall slightly in front (default forward direction)
        return rl.Vector3{
            .x = ctx.self.position.x + 40.0,
            .y = 0,
            .z = ctx.self.position.z,
        };
    }

    // Find closest enemy
    var closest_enemy = ctx.enemies[0];
    var closest_dist = ctx.self.distanceTo(closest_enemy.*);

    for (ctx.enemies[1..ctx.enemies_count]) |enemy| {
        const dist = ctx.self.distanceTo(enemy.*);
        if (dist < closest_dist) {
            closest_dist = dist;
            closest_enemy = enemy;
        }
    }

    // Place wall 40% of the way toward closest enemy (defensive position)
    const dx = closest_enemy.position.x - ctx.self.position.x;
    const dz = closest_enemy.position.z - ctx.self.position.z;

    return rl.Vector3{
        .x = ctx.self.position.x + dx * 0.4,
        .y = 0,
        .z = ctx.self.position.z + dz * 0.4,
    };
}

// Actions (can return success/failure/running)
pub const Actions = struct {
    // Move toward target
    pub fn moveToTarget(ctx: *BehaviorContext) NodeStatus {
        if (ctx.target == null) return .failure;
        // Movement handled by calculateMovementIntent - just signal success
        return .success;
    }

    // Cast best damage skill on target (cover-aware)
    pub fn castDamageSkill(ctx: *BehaviorContext) NodeStatus {
        if (ctx.target == null) return .failure;
        const target = ctx.target.?;

        // Check if target has cover (wall between us)
        const target_has_cover = ctx.terrain_grid.hasWallBetween(
            ctx.self.position.x,
            ctx.self.position.z,
            target.position.x,
            target.position.z,
            10.0,
        );

        if (selectDamageSkillWithCover(ctx.self, target, ctx.rng, target_has_cover)) |skill_idx| {
            const result = combat.tryStartCast(
                ctx.self,
                skill_idx,
                ctx.target,
                ctx.target_id,
                ctx.rng,
                ctx.vfx_manager,
                @constCast(ctx.terrain_grid),
            );

            if (result == .success or result == .casting_started) {
                ctx.ai_state.next_skill_time = ctx.ai_state.skill_cooldown;
                return .success;
            }
        }
        return .failure;
    }

    // Cast interrupt skill on target
    pub fn castInterrupt(ctx: *BehaviorContext) NodeStatus {
        if (ctx.target == null) return .failure;

        for (ctx.self.skill_bar, 0..) |maybe_skill, idx| {
            if (maybe_skill) |skill| {
                if (skill.interrupts and ctx.self.canUseSkill(@intCast(idx))) {
                    const result = combat.tryStartCast(
                        ctx.self,
                        @intCast(idx),
                        ctx.target,
                        ctx.target_id,
                        ctx.rng,
                        ctx.vfx_manager,
                        @constCast(ctx.terrain_grid),
                    );

                    if (result == .success or result == .casting_started) {
                        ctx.ai_state.next_skill_time = ctx.ai_state.skill_cooldown;
                        return .success;
                    }
                }
            }
        }
        return .failure;
    }

    // Cast terrain skill at strategic location
    pub fn castTerrainSkill(ctx: *BehaviorContext) NodeStatus {
        // Find a terrain skill
        for (ctx.self.skill_bar, 0..) |maybe_skill, idx| {
            if (maybe_skill) |skill| {
                if (skill.terrain_effect.shape != .none and ctx.self.canUseSkill(@intCast(idx))) {
                    const terrain_effect = skill.terrain_effect;

                    // Determine best target location
                    const target_pos = if (terrain_effect.heals_allies)
                        // Healing terrain: place near wounded allies
                        findBestAllyClumpLocation(ctx)
                    else if (terrain_effect.damages_enemies)
                        // Damaging terrain: place on enemy clumps
                        findBestEnemyClumpLocation(ctx)
                    else
                        // Utility terrain: place between self and enemies
                        findBestUtilityTerrainLocation(ctx);

                    if (target_pos) |pos| {
                        // Create temporary ground target
                        var ground_target = Character{
                            .id = 0,
                            .position = pos,
                            .previous_position = pos,
                            .radius = 0,
                            .color = .blue,
                            .school_color = .blue,
                            .position_color = .blue,
                            .name = "Ground",
                            .warmth = 100,
                            .max_warmth = 100,
                            .team = .red,
                            .school = .private_school,
                            .player_position = .pitcher,
                            .energy = 0,
                            .max_energy = 0,
                            .skill_bar = [_]?*const Skill{null} ** character.MAX_SKILLS,
                            .selected_skill = 0,
                        };

                        const result = combat.tryStartCast(
                            ctx.self,
                            @intCast(idx),
                            &ground_target,
                            null,
                            ctx.rng,
                            ctx.vfx_manager,
                            @constCast(ctx.terrain_grid),
                        );

                        if (result == .success or result == .casting_started) {
                            ctx.ai_state.next_skill_time = ctx.ai_state.skill_cooldown * 2.0; // Longer CD for terrain
                            return .success;
                        }
                    }
                }
            }
        }

        return .failure;
    }

    // Cast healing skill on lowest health ally
    pub fn castHeal(ctx: *BehaviorContext) NodeStatus {
        var lowest_health_pct: f32 = 1.0;
        var heal_target: ?*Character = null;
        var heal_target_id: ?EntityId = null;

        for (ctx.allies[0..ctx.allies_count]) |ally| {
            const health_pct = ally.warmth / ally.max_warmth;
            if (health_pct < lowest_health_pct) {
                lowest_health_pct = health_pct;
                heal_target = ally;
                heal_target_id = ally.id;
            }
        }

        // Fallback: heal self
        if (heal_target == null) {
            heal_target = ctx.self;
            heal_target_id = ctx.self.id;
        }

        // Find healing skill
        for (ctx.self.skill_bar, 0..) |maybe_skill, idx| {
            if (maybe_skill) |skill| {
                if (skill.healing > 0 and ctx.self.canUseSkill(@intCast(idx))) {
                    const result = combat.tryStartCast(
                        ctx.self,
                        @intCast(idx),
                        heal_target,
                        heal_target_id,
                        ctx.rng,
                        ctx.vfx_manager,
                        @constCast(ctx.terrain_grid),
                    );

                    if (result == .success or result == .casting_started) {
                        ctx.ai_state.next_skill_time = ctx.ai_state.skill_cooldown;
                        return .success;
                    }
                }
            }
        }

        return .failure;
    }

    // Cast wall-building skill to protect self or allies
    pub fn castDefensiveWall(ctx: *BehaviorContext) NodeStatus {
        // Find wall-building skill
        for (ctx.self.skill_bar, 0..) |maybe_skill, idx| {
            if (maybe_skill) |skill| {
                if (skill.creates_wall and ctx.self.canUseSkill(@intCast(idx))) {
                    // Calculate position: Between self and enemies
                    const target_pos = if (ctx.enemies_count > 0)
                        findBestDefensiveWallPosition(ctx)
                    else
                        ctx.self.position;

                    const result = combat.tryStartCastAtGround(
                        ctx.self,
                        @intCast(idx),
                        target_pos,
                        ctx.rng,
                        ctx.vfx_manager,
                        @constCast(ctx.terrain_grid),
                    );

                    if (result == .success or result == .casting_started) {
                        ctx.ai_state.next_skill_time = ctx.ai_state.skill_cooldown * 2.0; // Longer CD for walls
                        return .success;
                    }
                }
            }
        }

        return .failure;
    }

    // Cast wall-breaking skill on enemy walls
    pub fn castWallBreaker(ctx: *BehaviorContext) NodeStatus {
        if (ctx.target == null) return .failure;
        const target = ctx.target.?;

        // Check if there's a wall between us and target
        const has_wall = ctx.terrain_grid.hasWallBetween(
            ctx.self.position.x,
            ctx.self.position.z,
            target.position.x,
            target.position.z,
            10.0,
        );

        if (!has_wall) return .failure;

        // Find wall-breaking skill
        for (ctx.self.skill_bar, 0..) |maybe_skill, idx| {
            if (maybe_skill) |skill| {
                if (skill.destroys_walls and ctx.self.canUseSkill(@intCast(idx))) {
                    // Cast at midpoint between self and target (where wall likely is)
                    const wall_pos = rl.Vector3{
                        .x = (ctx.self.position.x + target.position.x) * 0.5,
                        .y = 0,
                        .z = (ctx.self.position.z + target.position.z) * 0.5,
                    };

                    const result = combat.tryStartCastAtGround(
                        ctx.self,
                        @intCast(idx),
                        wall_pos,
                        ctx.rng,
                        ctx.vfx_manager,
                        @constCast(ctx.terrain_grid),
                    );

                    if (result == .success or result == .casting_started) {
                        ctx.ai_state.next_skill_time = ctx.ai_state.skill_cooldown;
                        return .success;
                    }
                }
            }
        }

        return .failure;
    }
};

pub const SkillDecision = struct {
    skill_idx: u8,
    target_ally: bool, // true = target ally, false = target enemy
};

// ============================================================================
// ROLE-SPECIFIC BEHAVIOR TREES
// ============================================================================

// Damage Dealer: Defensive wall > Break walls > Interrupt > Terrain > Damage > Move
const DamageDealerTree = Selector(&[_]BehaviorNodeFn{
    Sequence(&[_]BehaviorNodeFn{
        Conditions.canCastSkill,
        Conditions.shouldBuildDefensiveWall,
        Actions.castDefensiveWall,
    }),
    Sequence(&[_]BehaviorNodeFn{
        Conditions.canCastSkill,
        Conditions.enemyWallBlocking,
        Actions.castWallBreaker,
    }),
    Sequence(&[_]BehaviorNodeFn{
        Conditions.canCastSkill,
        Conditions.targetCasting,
        Actions.castInterrupt,
    }),
    Sequence(&[_]BehaviorNodeFn{
        Conditions.canCastSkill,
        Conditions.shouldUseTerrainSkill,
        Actions.castTerrainSkill,
    }),
    Sequence(&[_]BehaviorNodeFn{
        Conditions.canCastSkill,
        Conditions.targetInRange,
        Actions.castDamageSkill,
    }),
    Actions.moveToTarget,
});

// Support: Heal allies > Protective walls > Healing Terrain > Buff/Terrain > Damage > Move
const SupportTree = Selector(&[_]BehaviorNodeFn{
    Sequence(&[_]BehaviorNodeFn{
        Conditions.canCastSkill,
        Conditions.allyNeedsHealing,
        Actions.castHeal,
    }),
    Sequence(&[_]BehaviorNodeFn{
        Conditions.canCastSkill,
        Conditions.underThreat, // Build wall when allies under threat
        Actions.castDefensiveWall,
    }),
    Sequence(&[_]BehaviorNodeFn{
        Conditions.canCastSkill,
        Conditions.allyNeedsHealing,
        Actions.castTerrainSkill, // Try healing terrain if heal fails
    }),
    Sequence(&[_]BehaviorNodeFn{
        Conditions.canCastSkill,
        Conditions.shouldUseTerrainSkill,
        Actions.castTerrainSkill,
    }),
    Sequence(&[_]BehaviorNodeFn{
        Conditions.canCastSkill,
        Conditions.targetInRange,
        Actions.castDamageSkill,
    }),
    Actions.moveToTarget,
});

// Disruptor: Always interrupt > Break walls > Terrain > Debuff > Damage
const DisruptorTree = Selector(&[_]BehaviorNodeFn{
    Sequence(&[_]BehaviorNodeFn{
        Conditions.canCastSkill,
        Conditions.targetCasting,
        Actions.castInterrupt,
    }),
    Sequence(&[_]BehaviorNodeFn{
        Conditions.canCastSkill,
        Conditions.enemyWallBlocking,
        Actions.castWallBreaker,
    }),
    Sequence(&[_]BehaviorNodeFn{
        Conditions.canCastSkill,
        Conditions.shouldUseTerrainSkill,
        Actions.castTerrainSkill,
    }),
    Sequence(&[_]BehaviorNodeFn{
        Conditions.canCastSkill,
        Conditions.targetInRange,
        Actions.castDamageSkill,
    }),
    Actions.moveToTarget,
});

// Behavior tree decision making
// Returns skill index and whether to target ally (true) or enemy (false)
fn selectSkillWithBehaviorTree(
    caster: *Character,
    target: *Character,
    all_entities: []Character,
    role: AIRole,
    rng: *std.Random,
) ?SkillDecision {
    switch (role) {
        .damage_dealer => {
            // No terrain grid here, assume no cover for fallback path
            if (selectDamageSkillWithCover(caster, target, rng, false)) |idx| {
                return SkillDecision{ .skill_idx = idx, .target_ally = false };
            }
            return null;
        },
        .support => return selectSupportSkill(caster, all_entities, rng),
        .disruptor => {
            if (selectDisruptorSkill(caster, target, rng)) |idx| {
                return SkillDecision{ .skill_idx = idx, .target_ally = false };
            }
            return null;
        },
    }
}

// Damage dealer: prioritize high damage, use interrupts on casting targets, build walls defensively
// Cover-aware: prefers arcing projectiles when target has cover
fn selectDamageSkillWithCover(caster: *Character, target: *Character, rng: *std.Random, target_has_cover: bool) ?u8 {
    // Check if we should build a defensive wall (low health + being attacked)
    const health_pct = caster.warmth / caster.max_warmth;
    if (health_pct < 0.5 and caster.damage_source_count > 0) {
        // Look for wall-building skill
        for (caster.skill_bar, 0..) |maybe_skill, idx| {
            if (maybe_skill) |skill| {
                if (skill.creates_wall and caster.canUseSkill(@intCast(idx))) {
                    // 50% chance to build defensive wall when low
                    if (rng.boolean()) {
                        return @intCast(idx);
                    }
                }
            }
        }
    }

    // Check if target is casting - use interrupt if available
    if (target.cast_state == .activating) {
        for (caster.skill_bar, 0..) |maybe_skill, idx| {
            if (maybe_skill) |skill| {
                if (skill.interrupts and caster.canUseSkill(@intCast(idx))) {
                    return @intCast(idx);
                }
            }
        }
    }

    // Use highest damage skill available, with cover awareness
    var best_skill: ?u8 = null;
    var best_damage: f32 = 0.0;

    for (caster.skill_bar, 0..) |maybe_skill, idx| {
        if (maybe_skill) |skill| {
            if (skill.damage > 0 and caster.canUseSkill(@intCast(idx))) {
                var effective_damage = skill.damage;

                // Prefer arcing projectiles when target has cover (they ignore walls)
                if (target_has_cover and skill.projectile_type == .arcing) {
                    effective_damage *= 1.5; // 50% preference boost for arcing when cover exists
                } else if (skill.projectile_type == .arcing) {
                    effective_damage *= 1.1; // Slight general preference for arcing
                }

                if (effective_damage > best_damage) {
                    best_damage = effective_damage;
                    best_skill = @intCast(idx);
                }
            }
        }
    }

    // Fallback: any available damage skill
    if (best_skill == null) {
        for (caster.skill_bar, 0..) |maybe_skill, idx| {
            if (maybe_skill) |skill| {
                if (skill.damage > 0 and caster.canUseSkill(@intCast(idx))) {
                    return @intCast(idx);
                }
            }
        }
    }

    return best_skill;
}

// Wall-breaking specialist: Use demolition/breakthrough skills to destroy enemy walls
fn selectWallBreakingSkill(caster: *Character, terrain_grid: *const @import("terrain.zig").TerrainGrid, target: *Character) ?u8 {
    // Check if there's a wall between us and the target
    const has_blocking_wall = terrain_grid.hasWallBetween(
        caster.position.x,
        caster.position.z,
        target.position.x,
        target.position.z,
        10.0, // Min wall height to care about
    );

    if (!has_blocking_wall) return null;

    // Find wall-breaking skill
    for (caster.skill_bar, 0..) |maybe_skill, idx| {
        if (maybe_skill) |skill| {
            if (skill.destroys_walls and caster.canUseSkill(@intCast(idx))) {
                // Found a wall-breaker! Use it!
                return @intCast(idx);
            }
        }
    }

    return null;
}

// Support: heal low health allies, buff team, protect with walls
// Returns skill index and whether it should be cast on an ally (true) or enemy (false)
fn selectSupportSkill(caster: *Character, all_entities: []Character, rng: *std.Random) ?SkillDecision {

    // Find lowest health ally (check all entities - player is in entities array now!)
    var lowest_health_pct: f32 = 1.0;
    var needs_healing = false;
    var ally_under_fire = false;

    // Check all allies in entities
    for (all_entities) |ent| {
        if (caster.isAlly(ent) and ent.isAlive()) {
            const health_pct = ent.warmth / ent.max_warmth;
            if (health_pct < lowest_health_pct) {
                lowest_health_pct = health_pct;
            }
            if (health_pct < 0.6) {
                needs_healing = true;
            }
            // Check if ally is taking damage (has active damage sources)
            if (health_pct < 0.7 and ent.damage_source_count > 0) {
                ally_under_fire = true;
            }
        }
    }

    // Build protective wall for ally if they're under fire (30% chance)
    if (ally_under_fire and rng.intRangeAtMost(u32, 0, 100) < 30) {
        for (caster.skill_bar, 0..) |maybe_skill, idx| {
            if (maybe_skill) |skill| {
                if (skill.creates_wall and caster.canUseSkill(@intCast(idx))) {
                    return SkillDecision{ .skill_idx = @intCast(idx), .target_ally = false };
                }
            }
        }
    }

    // Prioritize healing if ally is below 60% health
    if (needs_healing) {
        for (caster.skill_bar, 0..) |maybe_skill, idx| {
            if (maybe_skill) |skill| {
                if (skill.healing > 0 and caster.canUseSkill(@intCast(idx))) {
                    return SkillDecision{ .skill_idx = @intCast(idx), .target_ally = true };
                }
            }
        }
    }

    // Otherwise use buffs or damage
    for (caster.skill_bar, 0..) |maybe_skill, idx| {
        if (maybe_skill) |skill| {
            if ((skill.cozies.len > 0 or skill.damage > 0) and caster.canUseSkill(@intCast(idx))) {
                // Buffs should target allies, damage should target enemies
                const target_ally = skill.cozies.len > 0;
                return SkillDecision{ .skill_idx = @intCast(idx), .target_ally = target_ally };
            }
        }
    }

    return null;
}

// Disruptor: interrupt casts, apply debuffs
fn selectDisruptorSkill(caster: *Character, target: *Character, rng: *std.Random) ?u8 {

    // Always interrupt if target is casting
    if (target.cast_state == .activating) {
        for (caster.skill_bar, 0..) |maybe_skill, idx| {
            if (maybe_skill) |skill| {
                // Prefer interrupt skills, but also use daze-applying skills
                if ((skill.interrupts or skill.chills.len > 0) and caster.canUseSkill(@intCast(idx))) {
                    return @intCast(idx);
                }
            }
        }
    }

    // Apply debuffs if available
    for (caster.skill_bar, 0..) |maybe_skill, idx| {
        if (maybe_skill) |skill| {
            if (skill.chills.len > 0 and caster.canUseSkill(@intCast(idx))) {
                return @intCast(idx);
            }
        }
    }

    // Fallback to damage (assume no cover for disruptor fallback)
    return selectDamageSkillWithCover(caster, target, rng, false);
}

// Calculate movement intent for AI based on formation role and tactical situation
fn calculateFormationMovementIntent(
    ctx: *const BehaviorContext,
) MovementIntent {
    const ent = ctx.self;
    const target = ctx.target orelse {
        return MovementIntent{
            .local_x = 0.0,
            .local_z = 0.0,
            .facing_angle = 0.0,
            .apply_penalties = false,
        };
    };

    const formation_role = FormationRole.fromPosition(ent.player_position);
    const distance_to_target = ent.distanceTo(target.*);
    const anchors = ctx.formation_anchors;

    // Calculate direction to target
    const dx = target.position.x - ent.position.x;
    const dz = target.position.z - ent.position.z;
    const dist_xz = @sqrt(dx * dx + dz * dz);

    if (dist_xz < 0.1) {
        return MovementIntent{
            .local_x = 0.0,
            .local_z = 0.0,
            .facing_angle = 0.0,
            .apply_penalties = false,
        };
    }

    const dir_to_target_x = dx / dist_xz;
    const dir_to_target_z = dz / dist_xz;

    var move_world_x: f32 = 0.0;
    var move_world_z: f32 = 0.0;

    // Formation-aware positioning based on GW1 principles
    switch (formation_role) {
        .frontline => {
            // Frontline: Aggressive, holds the line, body blocks for backline
            // - Press forward toward enemies (within melee range)
            // - Stay between enemy and ally backline

            const optimal_range = ent.player_position.getRangeMin();
            const comfort_zone = 20.0;

            if (distance_to_target > optimal_range + comfort_zone) {
                // Too far, close distance aggressively
                move_world_x = dir_to_target_x;
                move_world_z = dir_to_target_z;
            } else if (distance_to_target < optimal_range * 0.5 - comfort_zone) {
                // Too close, back up slightly
                move_world_x = -dir_to_target_x * 0.5;
                move_world_z = -dir_to_target_z * 0.5;
            } else {
                // Good range, slight strafe for positioning
                const pos_hash = @abs(ent.position.x * 100 + ent.position.z * 100);
                const strafe_chance = @mod(@as(u32, @intFromFloat(pos_hash)), 100);
                if (strafe_chance < 20) {
                    const strafe_dir: f32 = if (@mod(@as(i32, @intFromFloat(ent.position.x * 10)), 2) == 0) 1.0 else -1.0;
                    move_world_x = -dir_to_target_z * strafe_dir * 0.5;
                    move_world_z = dir_to_target_x * strafe_dir * 0.5;
                }
            }
        },

        .midline => {
            // Midline: Maintain optimal range, avoid overextending
            // - Stay behind frontline, ahead of backline
            // - Kite if pressured, spread to avoid AoE

            const optimal_range = ent.player_position.getRangeMin();
            const max_range = ent.player_position.getRangeMax();
            const comfort_zone = 25.0;

            // Check if under threat (enemy too close)
            const under_threat = isUnderThreat(ent, ctx.enemies[0..ctx.enemies_count], ctx.enemies_count);

            if (under_threat and distance_to_target < optimal_range) {
                // KITE: Enemy too close, retreat while maintaining range
                move_world_x = -dir_to_target_x;
                move_world_z = -dir_to_target_z;
            } else if (distance_to_target > max_range * 0.85 + comfort_zone) {
                // Too far, advance (but not too aggressively)
                move_world_x = dir_to_target_x * 0.7;
                move_world_z = dir_to_target_z * 0.7;
            } else if (distance_to_target < optimal_range - comfort_zone) {
                // Too close, back away
                move_world_x = -dir_to_target_x * 0.6;
                move_world_z = -dir_to_target_z * 0.6;
            } else {
                // Good range, strafe for positioning
                const pos_hash = @abs(ent.position.x * 100 + ent.position.z * 100);
                const strafe_chance = @mod(@as(u32, @intFromFloat(pos_hash)), 120);
                if (strafe_chance < 30) {
                    const strafe_dir: f32 = if (@mod(@as(i32, @intFromFloat(ent.position.x * 10)), 2) == 0) 1.0 else -1.0;
                    move_world_x = -dir_to_target_z * strafe_dir;
                    move_world_z = dir_to_target_x * strafe_dir;
                }
            }

            // Apply spreading force to avoid clumping (AoE mitigation)
            const spread = calculateSpreadingForce(ent, ctx.allies[0..ctx.allies_count], ctx.allies_count);
            move_world_x += spread.x * 0.4; // Moderate spread influence
            move_world_z += spread.z * 0.4;
        },

        .backline => {
            // Backline: Stay safe, far from enemies, protected by frontline
            // - Maximum distance from enemy center
            // - Stay near other backliners for mutual protection
            // - Retreat if dove

            const safe_distance: f32 = 180.0;
            const danger_distance: f32 = 120.0;

            // Calculate distance to enemy center (not just target)
            const dx_enemy_center = anchors.enemy_center.x - ent.position.x;
            const dz_enemy_center = anchors.enemy_center.z - ent.position.z;
            const dist_to_enemy_center = @sqrt(dx_enemy_center * dx_enemy_center + dz_enemy_center * dz_enemy_center);

            const under_threat = isUnderThreat(ent, ctx.enemies[0..ctx.enemies_count], ctx.enemies_count);

            if (under_threat or dist_to_enemy_center < danger_distance) {
                // RETREAT: Being dove! Move away from enemy center
                if (dist_to_enemy_center > 0.1) {
                    move_world_x = -dx_enemy_center / dist_to_enemy_center;
                    move_world_z = -dz_enemy_center / dist_to_enemy_center;
                }
            } else if (dist_to_enemy_center < safe_distance) {
                // Too close to enemy center, back up
                if (dist_to_enemy_center > 0.1) {
                    move_world_x = -dx_enemy_center / dist_to_enemy_center * 0.7;
                    move_world_z = -dz_enemy_center / dist_to_enemy_center * 0.7;
                }
            } else if (dist_to_enemy_center > safe_distance * 1.5) {
                // Too far from team, move toward backline anchor
                const dx_backline = anchors.ally_backline_center.x - ent.position.x;
                const dz_backline = anchors.ally_backline_center.z - ent.position.z;
                const dist_backline = @sqrt(dx_backline * dx_backline + dz_backline * dz_backline);

                if (dist_backline > 50.0) {
                    move_world_x = dx_backline / dist_backline * 0.5;
                    move_world_z = dz_backline / dist_backline * 0.5;
                }
            } else {
                // Good position, slight adjustments only
                const pos_hash = @abs(ent.position.x * 100 + ent.position.z * 100);
                const strafe_chance = @mod(@as(u32, @intFromFloat(pos_hash)), 150);
                if (strafe_chance < 15) {
                    const strafe_dir: f32 = if (@mod(@as(i32, @intFromFloat(ent.position.x * 10)), 2) == 0) 1.0 else -1.0;
                    move_world_x = -dir_to_target_z * strafe_dir * 0.3;
                    move_world_z = dir_to_target_x * strafe_dir * 0.3;
                }
            }

            // Apply spreading force (backline should stay spread for safety)
            const spread = calculateSpreadingForce(ent, ctx.allies[0..ctx.allies_count], ctx.allies_count);
            move_world_x += spread.x * 0.5; // Strong spread influence for fragile backline
            move_world_z += spread.z * 0.5;
        },
    }

    return MovementIntent{
        .local_x = move_world_x,
        .local_z = move_world_z,
        .facing_angle = 0.0,
        .apply_penalties = false,
    };
}

// Helper: Populate behavior context with allies and enemies
fn populateContext(ctx: *BehaviorContext) void {
    ctx.allies_count = 0;
    ctx.enemies_count = 0;

    for (ctx.all_entities) |*ent| {
        if (!ent.isAlive()) continue;

        if (ctx.self.isAlly(ent.*)) {
            // Same team = ally
            if (ctx.allies_count < ctx.allies.len) {
                ctx.allies[ctx.allies_count] = ent;
                ctx.allies_count += 1;
            }
        } else {
            // Different team = enemy
            if (ctx.enemies_count < ctx.enemies.len) {
                ctx.enemies[ctx.enemies_count] = ent;
                ctx.enemies_count += 1;
            }
        }
    }

    // Calculate formation anchors
    ctx.formation_anchors = calculateFormationAnchors(&ctx.allies, &ctx.enemies, ctx.allies_count, ctx.enemies_count);
}

pub fn updateAI(
    entities: []Character,
    controlled_entity_id: EntityId,
    delta_time: f32,
    ai_states: []AIState,
    rng: *std.Random,
    vfx_manager: *@import("vfx.zig").VFXManager,
    terrain_grid: *const @import("terrain.zig").TerrainGrid,
) void {
    // Find the controlled player entity
    var player_ent: ?*Character = null;
    for (entities) |*e| {
        if (e.id == controlled_entity_id) {
            player_ent = e;
            break;
        }
    }

    for (entities, 0..) |*ent, i| {
        // Skip dead entities
        if (!ent.isAlive()) continue;

        // Skip the player-controlled entity (no AI for player!)
        if (ent.id == controlled_entity_id) continue;

        // Skip if no AI state for this entity
        if (i >= ai_states.len) continue;

        const ai_state = &ai_states[i];

        // Find target for movement and skills
        var target: ?*Character = null;
        var target_id: ?EntityId = null;

        if (player_ent) |player| {
            if (ent.isEnemy(player.*)) {
                // Enemies target player
                target = player;
                target_id = player.id;
            } else {
                // Allies target nearest enemy
                if (targeting.getNearestEnemy(ent.*, entities)) |enemy_id| {
                    // Find entity by ID
                    for (entities) |*e| {
                        if (e.id == enemy_id) {
                            target = e;
                            target_id = enemy_id;
                            break;
                        }
                    }
                } else {
                    // No enemies, follow player
                    target = player_ent;
                }
            }
        }

        // Create behavior context
        var ctx = BehaviorContext{
            .self = ent,
            .all_entities = entities,
            .ai_state = ai_state,
            .delta_time = delta_time,
            .rng = rng,
            .vfx_manager = vfx_manager,
            .terrain_grid = terrain_grid,
            .target = target,
            .target_id = target_id,
        };

        // Populate allies and enemies
        populateContext(&ctx);

        // Execute behavior tree based on role
        const tree_result = switch (ai_state.role) {
            .damage_dealer => DamageDealerTree(&ctx),
            .support => SupportTree(&ctx),
            .disruptor => DisruptorTree(&ctx),
        };

        _ = tree_result; // Result handled by tree actions

        // Auto-attack management: Enable auto-attack when idle and have a target
        if (target_id) |tid| {
            // If not currently auto-attacking this target, start auto-attacking
            if (!ent.is_auto_attacking or ent.auto_attack_target_id != tid) {
                // Only start auto-attack if we're in range and not casting
                if (ent.cast_state == .idle) {
                    if (target) |tgt| {
                        const distance = ent.distanceTo(tgt.*);
                        const attack_range = ent.getAutoAttackRange();

                        // Start auto-attacking if in range
                        if (distance <= attack_range) {
                            ent.startAutoAttack(tid);
                        }
                    }
                }
            }
        } else {
            // No target, stop auto-attacking
            if (ent.is_auto_attacking) {
                ent.stopAutoAttack();
            }
        }

        // Only move if not casting (GW1 rule: movement cancels/prevents casting)
        if (ent.cast_state == .idle) {
            // Calculate and apply formation-aware movement every tick
            const move_intent = calculateFormationMovementIntent(&ctx);
            movement.applyMovement(ent, move_intent, entities, null, null, delta_time, terrain_grid);
        }

        // Update skill casting timer
        ai_state.next_skill_time -= delta_time;
    }
}
