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
// AI SYSTEM OVERVIEW
// ============================================================================
//
// This AI system is designed around Guild Wars 1 (GW1) principles:
//
// 1. BEHAVIOR TREES: Hierarchical decision-making with Selectors (try until success)
//    and Sequences (do all in order). Each role (damage/support/disruptor) has its
//    own priority tree.
//
// 2. FORMATION ROLES: GW1-style frontline/midline/backline positioning where:
//    - Frontline: Melee fighters who hold the line and body-block for backline
//    - Midline: Ranged damage/control who kite and maintain optimal range
//    - Backline: Healers/support who stay safe, protected by frontline
//
// 3. SKILL SELECTION: Role-based priority (healers heal first, disruptors interrupt
//    first) with cover-awareness (prefer arcing projectiles over walls).
//
// 4. MOVEMENT: Formation-aware positioning that responds to threats, maintains
//    optimal ranges, and avoids AoE clumping through spreading forces.
//
// ============================================================================

// ============================================================================
// AI CONFIGURATION CONSTANTS
// ============================================================================

// ----------------------------------------------------------------------------
// Formation Positioning (in game units)
// ----------------------------------------------------------------------------
// These define the spatial relationships between team members and enemies.
// GW1 formations are critical for protecting fragile backline characters.

/// Formation positioning thresholds (in game units)
pub const FORMATION = struct {
    /// Distance from enemy center to be considered frontline - these characters
    /// engage enemies directly and protect teammates behind them
    pub const FRONTLINE_RANGE: f32 = 200.0;

    /// Safe distance for backline from enemy center - healers and support
    /// characters should stay at least this far from the enemy cluster
    pub const SAFE_DISTANCE: f32 = 180.0;

    /// Backline retreat threshold - if enemies get closer than this, backline
    /// characters should actively retreat (they're being "dove")
    pub const DANGER_DISTANCE: f32 = 120.0;

    /// Begin spreading when ally is this close - prevents AoE from hitting
    /// multiple teammates (GW1's "balling up" counter)
    pub const SPREAD_RADIUS: f32 = 40.0;

    /// Range tolerance for positioning - don't micro-adjust if within this
    /// distance of optimal position (prevents jittering)
    pub const COMFORT_ZONE: f32 = 20.0;
};

// ----------------------------------------------------------------------------
// Threat Detection
// ----------------------------------------------------------------------------
// Determines when AI characters should react defensively

/// Threat detection thresholds
pub const THREAT = struct {
    /// Enemy within this range is considered threatening - triggers defensive
    /// behaviors like kiting (midline) or retreat (backline)
    pub const CLOSE_RANGE: f32 = 150.0;
};

// ----------------------------------------------------------------------------
// Healing Priorities
// ----------------------------------------------------------------------------
// Thresholds for support AI to decide when healing is needed

/// Healing priorities
pub const HEALING = struct {
    /// Below 40% health = critical - support should prioritize healing immediately
    pub const CRITICAL_THRESHOLD: f32 = 0.4;

    /// Below 60% health = needs healing - support should look for healing opportunities
    pub const LOW_THRESHOLD: f32 = 0.6;
};

// ============================================================================
// BEHAVIOR TREE STRUCTURE
// ============================================================================
//
// Behavior trees provide hierarchical decision-making for AI. Each node returns
// one of three statuses:
//   - success: Action completed or condition met
//   - failure: Action failed or condition not met
//   - running: Action in progress (continue next frame)
//
// Two composite node types control flow:
//   - Selector: Try children in order until one succeeds (OR logic)
//   - Sequence: Run children in order, stop if any fails (AND logic)
//
// This allows complex behaviors like:
//   "If (can cast AND target casting) then interrupt, else damage, else move"
//

/// Behavior tree node status - the result of evaluating any node
pub const NodeStatus = enum {
    success, // Action completed successfully or condition is true
    failure, // Action failed or condition is false
    running, // Action still in progress (rare in our tick-based system)
};

/// Context passed to all behavior tree nodes - contains everything needed
/// for AI decision-making in a single frame
pub const BehaviorContext = struct {
    self: *Character,
    all_entities: []Character,
    ai_state: *AIState,
    delta_time: f32,
    rng: *std.Random,
    vfx_manager: *@import("vfx.zig").VFXManager,
    terrain_grid: *const @import("terrain.zig").TerrainGrid,
    match_telemetry: ?*@import("telemetry.zig").MatchTelemetry,

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

/// Base behavior tree node function pointer - all nodes share this signature
pub const BehaviorNodeFn = *const fn (ctx: *BehaviorContext) NodeStatus;

// ============================================================================
// AI ROLES AND FORMATION TYPES
// ============================================================================
//
// AI roles determine behavior priority (what to do first), while formation
// roles determine positioning (where to stand). These are orthogonal:
// a support can be frontline (paladin-style) or backline (traditional healer).
//

/// AI combat role - determines skill selection priority
/// This is the "what should I do?" question
pub const AIRole = enum {
    damage_dealer, // Focus on dealing damage, use interrupts opportunistically
    support, // Focus on healing/buffing allies, damage when team is healthy
    disruptor, // Focus on interrupts and debuffs, damage as fallback
};

/// GW1-style formation roles - determines positioning behavior
/// This is the "where should I stand?" question
pub const FormationRole = enum {
    frontline, // Melee/aggressive, holds the line, body blocks for backline
    midline, // Ranged damage/control, mobile, kites when pressured
    backline, // Healers/support, protected position, retreats when dove

    /// Classify player position into formation role
    /// Creates a balanced 2-2-2 distribution across the team
    pub fn fromPosition(pos: Position) FormationRole {
        return switch (pos) {
            // Close range melee - aggressive skirmisher + tank
            .sledder, .shoveler => .frontline,
            // Ranged damage dealers - pure DPS + generalist
            .pitcher, .fielder => .midline,
            // Support/control - summoner + healer
            .animator, .thermos => .backline,
        };
    }
};

/// Per-entity AI state - tracks timing and role assignment
pub const AIState = struct {
    /// Cooldown timer for AI skill decisions (prevents spam)
    next_skill_time: f32 = 0.0,
    /// Minimum seconds between AI skill casts - GW1-like frequent decisions,
    /// individual skill cooldowns enforce actual recharge
    skill_cooldown: f32 = 0.2,
    /// Combat role determining skill priority
    role: AIRole = .damage_dealer,
    /// Formation role determining positioning
    formation_role: FormationRole = .midline,
};

/// Skill decision result from behavior tree
pub const SkillDecision = struct {
    skill_idx: u8,
    target_ally: bool, // true = target ally, false = target enemy
};

// ============================================================================
// FORMATION CALCULATIONS
// ============================================================================
//
// Formation anchors are key positions used by the AI to maintain GW1-style
// team formations. They include:
//   - team_center: Average position of all allies
//   - ally_frontline_center: Average position of allies near enemies
//   - ally_backline_center: Average position of allies far from enemies
//   - enemy_center: Average position of all enemies
//
// These anchors help backline characters know where to retreat to, frontline
// characters know where to hold, and midline characters know safe distances.
//

/// Formation anchor points for team positioning
pub const FormationAnchors = struct {
    team_center: rl.Vector3,
    ally_frontline_center: rl.Vector3,
    ally_backline_center: rl.Vector3,
    enemy_center: rl.Vector3,
};

/// Calculate formation anchors from current ally and enemy positions
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

// ----------------------------------------------------------------------------
// Tactical Assessment Helpers
// ----------------------------------------------------------------------------

/// Check if character is under threat (any enemy within close range)
/// Used by midline/backline to trigger kiting or retreat behavior
pub fn isUnderThreat(self: *const Character, enemies: []const *Character, enemies_count: usize) bool {
    for (enemies[0..enemies_count]) |enemy| {
        const dist = self.distanceTo(enemy.*);
        if (dist < THREAT.CLOSE_RANGE) return true;
    }
    return false;
}

/// Find closest ally in a given formation role (useful for coordinated positioning)
pub fn findClosestAllyInRole(self: *const Character, allies: []const *Character, allies_count: usize, role: FormationRole) ?*Character {
    var closest: ?*Character = null;
    var closest_dist: f32 = std.math.floatMax(f32);

    for (allies[0..allies_count]) |ally| {
        if (ally.id == self.id) continue;

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

/// Calculate spreading force to avoid clumping (repulsion from nearby allies)
/// This is the GW1 "don't ball up" mechanic - prevents AoE from hitting multiple targets
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

// ----------------------------------------------------------------------------
// Behavior Tree Composite Nodes
// ----------------------------------------------------------------------------
// Composite nodes control the flow of execution through child nodes.

/// Selector: Try children in order until one succeeds (OR logic)
/// Returns first non-failure result, or failure if all children fail.
/// Use for "try this, else try that, else try this other thing"
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

/// Sequence: Run children in order, stop if any fails (AND logic)
/// Returns first non-success result, or success if all children succeed.
/// Use for "do this, then do that, then do this other thing"
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

// ============================================================================
// BEHAVIOR TREE LEAF NODES (Conditions and Actions)
// ============================================================================
//
// Leaf nodes are the actual work of the behavior tree:
//   - Conditions: Check game state, return success/failure (never running)
//   - Actions: Perform operations, can return any status
//

// ----------------------------------------------------------------------------
// Conditions - State checks that gate behavior tree branches
// ----------------------------------------------------------------------------
// All conditions return success/failure only (never running). They check the
// current game state without modifying it.

pub const Conditions = struct {
    /// Check if target is in range for any of our skills
    pub fn targetInRange(ctx: *BehaviorContext) NodeStatus {
        if (ctx.target == null) return .failure;
        const target = ctx.target.?;
        const distance = ctx.self.distanceTo(target.*);

        for (ctx.self.casting.skills) |maybe_skill| {
            if (maybe_skill) |skill| {
                if (distance <= skill.cast_range) return .success;
            }
        }
        return .failure;
    }

    /// Check if target is casting (interruptible) - key for disruptor role
    pub fn targetCasting(ctx: *BehaviorContext) NodeStatus {
        if (ctx.target == null) return .failure;
        return if (ctx.target.?.casting.state == .activating) .success else .failure;
    }

    /// Check if any ally needs healing (below 60% warmth)
    pub fn allyNeedsHealing(ctx: *BehaviorContext) NodeStatus {
        for (ctx.allies[0..ctx.allies_count]) |ally| {
            const health_pct = ally.stats.warmth / ally.stats.max_warmth;
            if (health_pct < HEALING.LOW_THRESHOLD) return .success;
        }
        return .failure;
    }

    /// Check if skill is ready to cast - currently always true since
    /// individual skill cooldowns are checked in canUseSkill()
    pub fn canCastSkill(_: *BehaviorContext) NodeStatus {
        return .success;
    }

    /// Check if self is under threat (below critical health threshold)
    pub fn underThreat(ctx: *BehaviorContext) NodeStatus {
        const health_pct = ctx.self.stats.warmth / ctx.self.stats.max_warmth;
        return if (health_pct < HEALING.CRITICAL_THRESHOLD) .success else .failure;
    }

    /// Check if it's a good time to use terrain skill (20% random chance)
    /// This adds variety to terrain skill usage rather than spamming
    pub fn shouldUseTerrainSkill(ctx: *BehaviorContext) NodeStatus {
        const roll = ctx.rng.intRangeAtMost(u32, 0, 100);
        return if (roll < 20) .success else .failure;
    }

    /// Check if there's an enemy wall blocking line of sight to target
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

    /// Check if we should build a defensive wall (low health + taking damage)
    pub fn shouldBuildDefensiveWall(ctx: *BehaviorContext) NodeStatus {
        const health_pct = ctx.self.stats.warmth / ctx.self.stats.max_warmth;
        const under_fire = ctx.self.combat.damage_monitor.count > 0;

        // Build wall if low health AND under fire (50% chance to add variety)
        if (health_pct < 0.5 and under_fire) {
            return if (ctx.rng.boolean()) .success else .failure;
        }

        return .failure;
    }

    /// Execute a queued skill if we're now in range
    pub fn executeQueuedSkill(ctx: *BehaviorContext) NodeStatus {
        if (!ctx.self.hasQueuedSkill()) return .failure;

        // Track that we're trying to execute queued skill
        if (ctx.match_telemetry) |tel| {
            tel.recordExecuteQueueCall(ctx.self.id);
        }

        const queued = ctx.self.casting.queued_skill orelse return .failure;
        const queued_skill_idx = queued.skill_index;
        const queued_target_id = queued.target_id;

        // Get skill
        const skill = ctx.self.casting.skills[queued_skill_idx] orelse {
            ctx.self.clearSkillQueue();
            return .failure;
        };

        // Find queued target
        var queued_target: ?*Character = null;
        for (ctx.all_entities) |*ent| {
            if (ent.id == queued_target_id) {
                queued_target = ent;
                break;
            }
        }

        if (queued_target == null) {
            ctx.self.clearSkillQueue();
            return .failure;
        }

        const target = queued_target.?;

        // Check if target is still alive
        if (!target.isAlive()) {
            if (ctx.match_telemetry) |tel| {
                tel.recordExecuteQueueTargetDead(ctx.self.id);
            }
            ctx.self.clearSkillQueue();
            return .failure;
        }

        // Check if in range now
        const distance = ctx.self.distanceTo(target.*);
        if (distance <= skill.cast_range) {
            // In range! Try to execute
            const result = combat.tryStartCast(
                ctx.self,
                queued_skill_idx,
                target,
                queued_target_id,
                ctx.rng,
                ctx.vfx_manager,
                @constCast(ctx.terrain_grid),
                ctx.match_telemetry,
            );

            if (result == .success or result == .casting_started) {
                if (ctx.match_telemetry) |tel| {
                    tel.recordExecuteQueueSuccess(ctx.self.id);
                }
                ctx.self.clearSkillQueue();
                return .success;
            } else if (result == .out_of_range) {
                // Still out of range? This shouldn't happen, but keep queue
                if (ctx.match_telemetry) |tel| {
                    tel.recordExecuteQueueOutOfRange(ctx.self.id);
                }
                return .failure;
            } else {
                // Other failure (energy, cooldown, etc) - keep queue to retry
                if (ctx.match_telemetry) |tel| {
                    tel.recordExecuteQueueNoEnergy(ctx.self.id);
                }
                return .failure;
            }
        }

        // Still out of range - return failure but keep queue
        // Movement is handled by calculateFormationMovementIntent
        // Next frame will check again if we're in range
        if (ctx.match_telemetry) |tel| {
            tel.recordExecuteQueueOutOfRange(ctx.self.id);
        }
        return .failure;
    }
};

// ============================================================================
// TERRAIN SKILL PLACEMENT HELPERS
// ============================================================================
//
// These functions determine optimal locations for ground-targeted skills.
// Healing terrain should be placed on wounded allies, damage terrain on
// enemy clusters, utility terrain between caster and threats.
//

/// Calculate the maximum cast range available to a character across all their skills
fn getMaxSkillRange(ent: *Character) f32 {
    var max_range: f32 = 100.0; // Fallback default

    for (ent.casting.skills) |maybe_skill| {
        if (maybe_skill) |skill| {
            if (skill.cast_range > max_range) {
                max_range = skill.cast_range;
            }
        }
    }

    return max_range;
}

/// Find the center of wounded allies for healing terrain placement
fn findBestAllyClumpLocation(ctx: *BehaviorContext) ?rl.Vector3 {
    var center = rl.Vector3{ .x = 0, .y = 0, .z = 0 };
    var wounded_count: usize = 0;

    for (ctx.allies[0..ctx.allies_count]) |ally| {
        const health_pct = ally.stats.warmth / ally.stats.max_warmth;
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

/// Find the best enemy cluster center for AoE damage terrain
fn findBestEnemyClumpLocation(ctx: *BehaviorContext) ?rl.Vector3 {
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

// ----------------------------------------------------------------------------
// Actions - Behavior tree nodes that perform game actions
// ----------------------------------------------------------------------------
// Actions can modify game state (cast skills, trigger movement). They return
// success if the action completed, failure if it couldn't be performed, or
// running if still in progress (rare in our tick-based system).

pub const Actions = struct {
    /// Move toward target - signals movement system, actual movement happens in
    /// calculateFormationMovementIntent
    pub fn moveToTarget(ctx: *BehaviorContext) NodeStatus {
        if (ctx.target == null) return .failure;
        return .success;
    }

    /// Cast best damage skill on target, preferring arcing projectiles when
    /// target has cover (wall between us). This is the core damage dealer action.
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

        if (ctx.match_telemetry) |tel| {
            tel.recordCastingAttempts(ctx.self.id);
        }
        if (selectDamageSkillWithCover(ctx.self, target, ctx.rng, target_has_cover)) |skill_idx| {
            const result = combat.tryStartCast(
                ctx.self,
                skill_idx,
                ctx.target,
                ctx.target_id,
                ctx.rng,
                ctx.vfx_manager,
                @constCast(ctx.terrain_grid),
                ctx.match_telemetry,
            );

            if (result == .success or result == .casting_started) {
                return .success;
            }

            // Track why cast failed (for debugging)
            if (ctx.match_telemetry) |tel| {
                switch (result) {
                    .on_cooldown => tel.recordCooldownBlock(ctx.self.id),
                    .no_energy => tel.recordNoEnergyBlock(ctx.self.id),
                    .out_of_range => {}, // Already tracked in tryStartCast
                    else => {},
                }
            }
        }
        return .failure;
    }

    // Cast interrupt skill on target
    pub fn castInterrupt(ctx: *BehaviorContext) NodeStatus {
        if (ctx.target == null) return .failure;

        for (ctx.self.casting.skills, 0..) |maybe_skill, idx| {
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
                        ctx.match_telemetry,
                    );

                    if (result == .success or result == .casting_started) {
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
        for (ctx.self.casting.skills, 0..) |maybe_skill, idx| {
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
                            .team = .red,
                            .school = .private_school,
                            .player_position = .pitcher,
                            .stats = .{
                                .warmth = 100,
                                .max_warmth = 100,
                                .energy = 0,
                                .max_energy = 0,
                            },
                            .casting = .{
                                .selected_index = 0,
                            },
                        };

                        const result = combat.tryStartCast(
                            ctx.self,
                            @intCast(idx),
                            &ground_target,
                            null,
                            ctx.rng,
                            ctx.vfx_manager,
                            @constCast(ctx.terrain_grid),
                            ctx.match_telemetry,
                        );

                        if (result == .success or result == .casting_started) {
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
            const health_pct = ally.stats.warmth / ally.stats.max_warmth;
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
        for (ctx.self.casting.skills, 0..) |maybe_skill, idx| {
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
                        ctx.match_telemetry,
                    );

                    if (result == .success or result == .casting_started) {
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
        for (ctx.self.casting.skills, 0..) |maybe_skill, idx| {
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
                        ctx.match_telemetry,
                    );

                    if (result == .success or result == .casting_started) {
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
        for (ctx.self.casting.skills, 0..) |maybe_skill, idx| {
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
                        ctx.match_telemetry,
                    );

                    if (result == .success or result == .casting_started) {
                        return .success;
                    }
                }
            }
        }

        return .failure;
    }
};

// ============================================================================
// ROLE-SPECIFIC BEHAVIOR TREES
// ============================================================================
//
// Each AI role has its own behavior tree defining priority order:
//   - Damage Dealer: Defensive wall > Break walls > Interrupt > Terrain > Damage > Move
//   - Support: Heal allies > Protective walls > Healing terrain > Terrain > Damage > Move
//   - Disruptor: Interrupt always > Break walls > Terrain > Damage > Move
//

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
        Actions.castDamageSkill,
    }),
    Actions.moveToTarget,
});

// ============================================================================
// SKILL SELECTION FUNCTIONS
// ============================================================================
//
// These functions implement role-specific skill selection logic. Each role
// has different priorities:
//   - Damage: High damage > Interrupts > Walls (when low health)
//   - Support: Heals > Protective walls > Buffs > Damage
//   - Disruptor: Interrupts > Debuffs > Damage
//
// Cover awareness: When a wall blocks line of sight to target, prefer arcing
// projectiles (snowballs that go over walls) over direct projectiles.
//

/// Behavior tree decision making entry point
/// Returns skill index and whether to target ally (true) or enemy (false)
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

// ----------------------------------------------------------------------------
// Damage Dealer Skill Selection
// ----------------------------------------------------------------------------

/// Select best damage skill, with cover awareness for arcing projectiles.
/// Priority: Defensive wall (when low) > Interrupt (if target casting) > Highest damage
fn selectDamageSkillWithCover(caster: *Character, target: *Character, rng: *std.Random, target_has_cover: bool) ?u8 {
    // Check if we should build a defensive wall (low health + being attacked)
    const health_pct = caster.stats.warmth / caster.stats.max_warmth;
    if (health_pct < 0.5 and caster.combat.damage_monitor.count > 0) {
        for (caster.casting.skills, 0..) |maybe_skill, idx| {
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
    if (target.casting.state == .activating) {
        for (caster.casting.skills, 0..) |maybe_skill, idx| {
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

    for (caster.casting.skills, 0..) |maybe_skill, idx| {
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
        for (caster.casting.skills, 0..) |maybe_skill, idx| {
            if (maybe_skill) |skill| {
                if (skill.damage > 0 and caster.canUseSkill(@intCast(idx))) {
                    return @intCast(idx);
                }
            }
        }
    }

    return best_skill;
}

// ----------------------------------------------------------------------------
// Wall-Breaking Skill Selection
// ----------------------------------------------------------------------------

/// Select wall-breaking skill if an enemy wall blocks line of sight to target
fn selectWallBreakingSkill(caster: *Character, terrain_grid: *const @import("terrain.zig").TerrainGrid, target: *Character) ?u8 {
    const has_blocking_wall = terrain_grid.hasWallBetween(
        caster.position.x,
        caster.position.z,
        target.position.x,
        target.position.z,
        10.0, // Min wall height to care about
    );

    if (!has_blocking_wall) return null;

    // Find wall-breaking skill
    for (caster.casting.skills, 0..) |maybe_skill, idx| {
        if (maybe_skill) |skill| {
            if (skill.destroys_walls and caster.canUseSkill(@intCast(idx))) {
                return @intCast(idx);
            }
        }
    }

    return null;
}

// ----------------------------------------------------------------------------
// Support Skill Selection
// ----------------------------------------------------------------------------

/// Select support skill - heals, protective walls, or buffs
/// Priority: Protective wall (ally under fire) > Heal (ally hurt) > Buff/Damage
fn selectSupportSkill(caster: *Character, all_entities: []Character, rng: *std.Random) ?SkillDecision {
    // Find lowest health ally (player is in entities array)
    var lowest_health_pct: f32 = 1.0;
    var needs_healing = false;
    var ally_under_fire = false;

    for (all_entities) |ent| {
        if (caster.isAlly(ent) and ent.isAlive()) {
            const health_pct = ent.stats.warmth / ent.stats.max_warmth;
            if (health_pct < lowest_health_pct) {
                lowest_health_pct = health_pct;
            }
            if (health_pct < 0.6) {
                needs_healing = true;
            }
            // Check if ally is taking damage (has active damage sources)
            if (health_pct < 0.7 and ent.combat.damage_monitor.count > 0) {
                ally_under_fire = true;
            }
        }
    }

    // Build protective wall for ally if they're under fire (30% chance)
    if (ally_under_fire and rng.intRangeAtMost(u32, 0, 100) < 30) {
        for (caster.casting.skills, 0..) |maybe_skill, idx| {
            if (maybe_skill) |skill| {
                if (skill.creates_wall and caster.canUseSkill(@intCast(idx))) {
                    return SkillDecision{ .skill_idx = @intCast(idx), .target_ally = false };
                }
            }
        }
    }

    // Prioritize healing if ally is below 60% health
    if (needs_healing) {
        for (caster.casting.skills, 0..) |maybe_skill, idx| {
            if (maybe_skill) |skill| {
                if (skill.healing > 0 and caster.canUseSkill(@intCast(idx))) {
                    return SkillDecision{ .skill_idx = @intCast(idx), .target_ally = true };
                }
            }
        }
    }

    // Otherwise use buffs or damage
    for (caster.casting.skills, 0..) |maybe_skill, idx| {
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

// ----------------------------------------------------------------------------
// Disruptor Skill Selection
// ----------------------------------------------------------------------------

/// Select disruptor skill - prioritizes interrupts and debuffs
/// Priority: Interrupt (if target casting) > Debuffs (chills) > Damage (fallback)
fn selectDisruptorSkill(caster: *Character, target: *Character, rng: *std.Random) ?u8 {
    // Always interrupt if target is casting
    if (target.casting.state == .activating) {
        for (caster.casting.skills, 0..) |maybe_skill, idx| {
            if (maybe_skill) |skill| {
                // Prefer interrupt skills, but also use daze-applying skills
                if ((skill.interrupts or skill.chills.len > 0) and caster.canUseSkill(@intCast(idx))) {
                    return @intCast(idx);
                }
            }
        }
    }

    // Apply debuffs if available
    for (caster.casting.skills, 0..) |maybe_skill, idx| {
        if (maybe_skill) |skill| {
            if (skill.chills.len > 0 and caster.canUseSkill(@intCast(idx))) {
                return @intCast(idx);
            }
        }
    }

    // Fallback to damage (assume no cover for disruptor fallback)
    return selectDamageSkillWithCover(caster, target, rng, false);
}

// ============================================================================
// FORMATION MOVEMENT SYSTEM
// ============================================================================
//
// GW1-style formation movement where each role has different positioning goals:
//
// FRONTLINE: Press forward toward enemies, stay within melee/short range,
//   position between enemies and backline allies. Body-blocks for teammates.
//
// MIDLINE: Maintain optimal attack range, kite backward when pressured,
//   spread out to avoid AoE damage. More mobile than other roles.
//
// BACKLINE: Stay far from enemy center, retreat when "dove" (enemies rushing
//   the backline), cluster with other backliners for mutual protection.
//
// All roles apply "spreading force" - a soft repulsion from nearby allies
// to prevent AoE damage from hitting multiple teammates ("don't ball up").
//

/// Calculate movement intent for AI based on formation role and tactical situation
fn calculateFormationMovementIntent(
    ctx: *const BehaviorContext,
) MovementIntent {
    const ent = ctx.self;

    // PRIORITY: If we have a queued skill, move toward THAT target, not the main target
    var target = ctx.target orelse {
        return MovementIntent{
            .local_x = 0.0,
            .local_z = 0.0,
            .facing_angle = 0.0,
            .apply_penalties = false,
        };
    };

    // If queued skill exists, find its target and use that instead
    if (ent.hasQueuedSkill()) {
        if (ent.casting.queued_skill) |queued| {
            for (ctx.all_entities) |*potential_target| {
                if (potential_target.id == queued.target_id) {
                    target = potential_target;
                    break;
                }
            }
        }
    }

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

            // Use actual skill range - must be IN RANGE to cast!
            const max_skill_range = getMaxSkillRange(ent);
            // Use max skill range, not min, so frontline can actually reach targets!
            const optimal_range = max_skill_range;
            const comfort_zone = 10.0;
            // Less aggressive buffer - push closer to ensure in-range
            const desired_range = optimal_range - 50.0;

            if (distance_to_target > desired_range + comfort_zone) {
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

    // Convert world-space movement to local space (relative to facing direction)
    // and face the target
    const facing_angle = ent.facing_angle;
    const cos_angle = @cos(facing_angle);
    const sin_angle = @sin(facing_angle);

    // Rotate world-space movement to local space (inverse of the world-space rotation)
    // This converts world velocity to character-relative velocity
    // Local: x = right, z = forward/backward (relative to facing)
    const local_x = move_world_x * cos_angle + move_world_z * sin_angle;
    const local_z = -move_world_x * sin_angle + move_world_z * cos_angle;

    return MovementIntent{
        .local_x = local_x,
        .local_z = local_z,
        .facing_angle = facing_angle,
        .apply_penalties = true, // Re-enable movement penalties for realistic movement
    };
}

/// Populate behavior context with allies and enemies from entity list
fn populateContext(ctx: *BehaviorContext) void {
    ctx.allies_count = 0;
    ctx.enemies_count = 0;

    for (ctx.all_entities) |*ent| {
        if (!ent.isAlive()) continue;

        if (ctx.self.isAlly(ent.*)) {
            if (ctx.allies_count < ctx.allies.len) {
                ctx.allies[ctx.allies_count] = ent;
                ctx.allies_count += 1;
            }
        } else {
            if (ctx.enemies_count < ctx.enemies.len) {
                ctx.enemies[ctx.enemies_count] = ent;
                ctx.enemies_count += 1;
            }
        }
    }

    // Calculate formation anchors for positioning
    ctx.formation_anchors = calculateFormationAnchors(&ctx.allies, &ctx.enemies, ctx.allies_count, ctx.enemies_count);
}

// ============================================================================
// MAIN AI UPDATE LOOP
// ============================================================================
//
// Called each frame to update all AI-controlled entities. The loop:
// 1. Finds targets (player-controlled entity or nearest enemy)
// 2. Creates behavior context with allies/enemies/formation data
// 3. Runs the appropriate behavior tree based on AI role
// 4. Manages auto-attack state
// 5. Applies formation-aware movement (if not casting)
//

/// Main AI update function - processes all AI-controlled entities each frame
pub fn updateAI(
    entities: []Character,
    controlled_entity_id: EntityId,
    delta_time: f32,
    ai_states: []AIState,
    rng: *std.Random,
    vfx_manager: *@import("vfx.zig").VFXManager,
    terrain_grid: *const @import("terrain.zig").TerrainGrid,
    match_telemetry: ?*@import("telemetry.zig").MatchTelemetry,
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
        if (ent.id == controlled_entity_id) {
            // Debug: track skipped entities
            continue;
        }

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
        } else {
            // AI-only mode: no player, so everyone targets nearest enemy
            if (targeting.getNearestEnemy(ent.*, entities)) |enemy_id| {
                // Find entity by ID
                for (entities) |*e| {
                    if (e.id == enemy_id) {
                        target = e;
                        target_id = enemy_id;
                        break;
                    }
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
            .match_telemetry = match_telemetry,
            .target = target,
            .target_id = target_id,
        };

        // Populate allies and enemies
        populateContext(&ctx);

        // Track target_id for debugging
        if (target_id) |_| {
            if (match_telemetry) |telem| {
                telem.recordTargetIdSet(ent.id);
            }
        } else {
            if (match_telemetry) |telem| {
                telem.recordTargetIdNone(ent.id);
            }
        }

        // PRIORITY: Check for queued skill
        if (ctx.self.hasQueuedSkill()) {
            // We have a queued skill - try to execute it
            const queued_result = Conditions.executeQueuedSkill(&ctx);
            if (queued_result == .success) {
                // Queued skill executed successfully
                // Continue to movement/auto-attack logic below
            }
            // If queued skill failed (out of range), DON'T run normal tree
            // Keep waiting for the unit to get in range
            // This ensures queued skills are never replaced by new decisions
        } else {
            // No queued skill, use normal AI decision tree
            const tree_result = switch (ai_state.role) {
                .damage_dealer => DamageDealerTree(&ctx),
                .support => SupportTree(&ctx),
                .disruptor => DisruptorTree(&ctx),
            };

            _ = tree_result; // Result handled by tree actions
        }

        // Auto-attack management: Enable auto-attack when idle and have a target
        if (target_id) |tid| {
            // If not currently auto-attacking this target, start auto-attacking
            if (!ent.combat.auto_attack.is_active or ent.combat.auto_attack.target_id != tid) {
                // Only start auto-attack if we're in range and not casting
                if (ent.casting.state == .idle) {
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
            if (ent.combat.auto_attack.is_active) {
                ent.stopAutoAttack();
            }
        }

        // Only move if not casting (GW1 rule: movement cancels/prevents casting)
        if (ent.casting.state == .idle) {
            // Calculate and apply formation-aware movement every tick
            const move_intent = calculateFormationMovementIntent(&ctx);

            // Track position before movement
            const pos_before = ent.position;

            movement.applyMovement(ent, move_intent, entities, null, null, delta_time, terrain_grid);

            // Record movement in telemetry
            if (ctx.match_telemetry) |telem| {
                // Calculate distance moved (2D in xz plane)
                const dx = ent.position.x - pos_before.x;
                const dz = ent.position.z - pos_before.z;
                const distance_moved = @sqrt(dx * dx + dz * dz);

                if (distance_moved > 0.01) {
                    const is_forward = move_intent.local_z < 0.0; // Forward in local space is negative Z
                    telem.recordMovement(ent.id, distance_moved, is_forward);
                    telem.recordMovementVector(ent.id, move_intent.local_x, move_intent.local_z);
                }
            }
        }

        // Update skill casting timer
    }
}
