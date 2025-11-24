const std = @import("std");
const combat = @import("combat.zig");
const character = @import("character.zig");
const skills = @import("skills.zig");

const print = std.debug.print;

/// Timeline event for tracking match arc
pub const TimelineEvent = struct {
    tick: u32,
    event_type: EventType,
    entity_id: u32,
    data: EventData,

    pub const EventType = enum {
        damage_dealt,
        healing_done,
        kill,
        death,
        skill_cast,
        condition_applied,
        position_change, // For analyzing positioning phases
    };

    pub const EventData = union {
        damage: struct {
            amount: f32,
            skill_name: []const u8,
        },
        healing: struct {
            amount: f32,
            skill_name: []const u8,
        },
        kill: struct {
            victim_id: u32,
        },
        skill_cast: struct {
            skill_name: []const u8,
            success: bool,
        },
        condition: struct {
            condition_name: []const u8,
            target_id: u32,
        },
        position: struct {
            x: f32,
            z: f32,
            distance_to_enemies: f32,
        },
    };
};

/// Per-entity statistics tracked during a match
pub const EntityStats = struct {
    entity_id: u32,
    name: []const u8,
    school: []const u8,
    position: []const u8, // "melee", "ranged", "support", etc
    team: u8, // 0 = ally, 1 = enemy
    is_player: bool,

    // Damage metrics
    damage_dealt: f32 = 0.0,
    damage_received: f32 = 0.0,
    damage_absorbed_by_walls: f32 = 0.0,
    damage_reduction_from_armor: f32 = 0.0,

    // Healing metrics
    healing_dealt: f32 = 0.0,
    healing_received: f32 = 0.0,
    overhealing: f32 = 0.0, // Healing when already at max HP

    // Skill usage
    skills_cast: u32 = 0,
    skills_failed: u32 = 0, // Out of range, no energy, etc
    energy_spent: f32 = 0.0,
    energy_regenerated: f32 = 0.0,

    // Combat efficiency
    kills: u32 = 0,
    deaths: u32 = 0,
    time_alive_ticks: u32 = 0,
    time_dead_ticks: u32 = 0,

    // Status effects applied
    conditions_applied: u32 = 0,
    conditions_cleansed: u32 = 0,

    // Position/movement
    distance_traveled: f32 = 0.0,
    out_of_range_attempts: u32 = 0,

    // AI Decision tracking (why aren't they fighting?)
    target_acquisitions: u32 = 0, // Times unit found a target
    casting_attempts: u32 = 0, // Times AI tried to cast a skill
    no_energy_blocks: u32 = 0, // Blocked by insufficient energy
    out_of_range_blocks: u32 = 0, // Blocked by range
    cooldown_blocks: u32 = 0, // Blocked by skill cooldown
    no_valid_target_blocks: u32 = 0, // No valid target for skill
    condition_fails: u32 = 0, // AI condition checks failed

    // Queue debugging
    queue_skill_calls: u32 = 0, // Times queueSkill was called
    execute_queue_calls: u32 = 0, // Times executeQueuedSkill was called
    execute_queue_success: u32 = 0, // Times queued skill was successfully cast
    execute_queue_out_of_range: u32 = 0, // Times queued skill still out of range
    execute_queue_no_energy: u32 = 0, // Times queued skill failed due to energy
    execute_queue_target_dead: u32 = 0, // Times queued target was dead
    movement_attempts: u32 = 0, // Times unit moved
    idle_ticks: u32 = 0, // Ticks spent doing nothing (not moving, not casting)

    // Target acquisition debugging
    target_id_set: u32 = 0, // Times target_id was successfully assigned
    target_id_none: u32 = 0, // Times target_id remained None

    // Movement tracking
    total_distance_moved: f32 = 0.0, // Total distance traveled toward enemies
    forward_movement_attempts: u32 = 0, // Times unit moved toward target
    movement_vectors_sum_x: f32 = 0.0, // Sum of all movement vectors X
    movement_vectors_sum_z: f32 = 0.0, // Sum of all movement vectors Z

    // Per-skill breakdown (map of skill name -> usage count)
    skill_usage: std.StringHashMap(SkillStats) = undefined,

    // Position-specific performance analysis
    position_metrics: PositionMetrics = .{},

    pub const PositionMetrics = struct {
        // For melee: how much damage from close range
        // For ranged: how well they maintained distance
        // For support: how much healing was done
        effective_range: f32 = 0.0, // Average effective combat range
        time_in_optimal_range: u32 = 0, // Ticks spent at optimal range for role
        time_out_of_optimal_range: u32 = 0, // Ticks spent at suboptimal range
        range_efficiency: f32 = 0.0, // Calculated as (damage_in_range / (damage_in_range + damage_out_range))

        pub fn calcRangeEfficiency(self: *const PositionMetrics) f32 {
            if (self.range_efficiency == 0) {
                const total = self.time_in_optimal_range + self.time_out_of_optimal_range;
                if (total == 0) return 0.0;
                return @as(f32, @floatFromInt(self.time_in_optimal_range)) / @as(f32, @floatFromInt(total));
            }
            return self.range_efficiency;
        }
    };

    pub fn init(allocator: std.mem.Allocator, entity_id: u32, name: []const u8, school: []const u8, position: []const u8, team: u8, is_player: bool) !EntityStats {
        const stats: EntityStats = .{
            .entity_id = entity_id,
            .name = name,
            .school = school,
            .position = position,
            .team = team,
            .is_player = is_player,
            .skill_usage = std.StringHashMap(SkillStats).init(allocator),
        };
        return stats;
    }

    pub fn deinit(self: *EntityStats) void {
        self.skill_usage.deinit();
    }

    /// Calculate damage after armor reduction
    pub fn calcEffectiveDamage(_: *const EntityStats, raw_damage: f32, armor: f32) f32 {
        const reduction = (armor / 100.0) * raw_damage;
        return @max(0.1, raw_damage - reduction); // Minimum 0.1 damage
    }

    /// Calculate combat efficiency rating (0.0 - 1.0)
    pub fn calcEfficiency(self: *const EntityStats) f32 {
        if (self.damage_received == 0) return 0.0;
        return self.damage_dealt / (self.damage_dealt + self.damage_received);
    }

    /// Get skill success rate
    pub fn getSkillSuccessRate(self: *const EntityStats) f32 {
        const total = self.skills_cast + self.skills_failed;
        if (total == 0) return 0.0;
        return @as(f32, @floatFromInt(self.skills_cast)) / @as(f32, @floatFromInt(total));
    }

    /// Calculate DPS (damage per second equivalent)
    pub fn calcDPS(self: *const EntityStats) f32 {
        if (self.time_alive_ticks == 0) return 0.0;
        const seconds = @as(f32, @floatFromInt(self.time_alive_ticks)) / 60.0; // Assuming 60 ticks/sec
        return self.damage_dealt / seconds;
    }

    /// Calculate casting rate (casts per tick)
    pub fn getCastRate(self: *const EntityStats) f32 {
        if (self.time_alive_ticks == 0) return 0.0;
        return @as(f32, @floatFromInt(self.skills_cast)) / @as(f32, @floatFromInt(self.time_alive_ticks));
    }

    /// Calculate why unit wasn't attacking
    pub fn getInactivityRate(self: *const EntityStats) f32 {
        if (self.time_alive_ticks == 0) return 0.0;
        return @as(f32, @floatFromInt(self.idle_ticks)) / @as(f32, @floatFromInt(self.time_alive_ticks));
    }

    /// Summarize main AI blockage reason
    pub fn getMainBlockageReason(self: *const EntityStats) []const u8 {
        var max_blocks: u32 = 0;
        var reason: []const u8 = "unknown";

        if (self.no_energy_blocks > max_blocks) {
            max_blocks = self.no_energy_blocks;
            reason = "no_energy";
        }
        if (self.out_of_range_blocks > max_blocks) {
            max_blocks = self.out_of_range_blocks;
            reason = "out_of_range";
        }
        if (self.cooldown_blocks > max_blocks) {
            max_blocks = self.cooldown_blocks;
            reason = "cooldown";
        }
        if (self.condition_fails > max_blocks) {
            max_blocks = self.condition_fails;
            reason = "condition_failed";
        }
        if (self.no_valid_target_blocks > max_blocks) {
            max_blocks = self.no_valid_target_blocks;
            reason = "no_target";
        }

        if (max_blocks == 0) {
            reason = "idle/no_attempts";
        }

        return reason;
    }
};

/// Per-skill statistics - detailed breakdown for balance analysis
pub const SkillStats = struct {
    skill_name: []const u8,
    casts: u32 = 0,
    failures: u32 = 0,

    // Damage breakdown
    total_damage: f32 = 0.0,
    min_damage: f32 = 0.0,
    max_damage: f32 = 0.0,
    damage_hits: u32 = 0, // Number of times this skill dealt damage

    // Healing breakdown
    total_healing: f32 = 0.0,
    total_overhealing: f32 = 0.0,
    healing_hits: u32 = 0, // Number of times this skill healed

    // Resource costs
    total_energy_cost: f32 = 0.0,

    // Condition effects (per-skill breakdown)
    conditions_applied: u32 = 0,
    // Map of condition name -> count for detailed analysis
    conditions_map: std.StringHashMap(u32) = undefined,

    pub fn init(allocator: std.mem.Allocator, skill_name: []const u8) !SkillStats {
        return .{
            .skill_name = skill_name,
            .conditions_map = std.StringHashMap(u32).init(allocator),
        };
    }

    pub fn deinit(self: *SkillStats) void {
        self.conditions_map.deinit();
    }

    pub fn recordDamage(self: *SkillStats, damage: f32) void {
        self.total_damage += damage;
        self.damage_hits += 1;
        if (self.min_damage == 0 or damage < self.min_damage) {
            self.min_damage = damage;
        }
        if (damage > self.max_damage) {
            self.max_damage = damage;
        }
    }

    pub fn recordHealing(self: *SkillStats, healing: f32, overhealing: f32) void {
        self.total_healing += healing;
        self.total_overhealing += overhealing;
        self.healing_hits += 1;
    }

    pub fn getAverageDamage(self: *const SkillStats) f32 {
        if (self.damage_hits == 0) return 0.0;
        return self.total_damage / @as(f32, @floatFromInt(self.damage_hits));
    }

    pub fn getAverageHealing(self: *const SkillStats) f32 {
        if (self.healing_hits == 0) return 0.0;
        return self.total_healing / @as(f32, @floatFromInt(self.healing_hits));
    }

    pub fn getSuccessRate(self: *const SkillStats) f32 {
        const total = self.casts + self.failures;
        if (total == 0) return 0.0;
        return @as(f32, @floatFromInt(self.casts)) / @as(f32, @floatFromInt(total));
    }
};

/// Complete match telemetry
pub const MatchTelemetry = struct {
    allocator: std.mem.Allocator,
    match_duration_ticks: u32 = 0,
    winning_team: ?u8 = null, // 0 = allies, 1 = enemies

    // Per-entity stats
    entities_array: [8]EntityStats = undefined,
    entities_count: usize = 0,

    // Aggregate stats
    total_damage_dealt_ally: f32 = 0.0,
    total_damage_dealt_enemy: f32 = 0.0,
    total_healing_ally: f32 = 0.0,
    total_healing_enemy: f32 = 0.0,

    // Timeline tracking for match arc analysis
    timeline_events: [1024]TimelineEvent = undefined,
    timeline_count: usize = 0,

    // School vs school matchup tracking
    school_matchups: std.StringHashMap(SchoolMatchupStats) = undefined,

    pub const SchoolMatchupStats = struct {
        total_damage: f32 = 0.0,
        total_damage_received: f32 = 0.0,
        total_kills: u32 = 0,
        total_deaths: u32 = 0,
        matches: u32 = 0,
        wins: u32 = 0,
    };

    pub fn init(allocator: std.mem.Allocator) !MatchTelemetry {
        return .{
            .allocator = allocator,
            .school_matchups = std.StringHashMap(SchoolMatchupStats).init(allocator),
        };
    }

    pub fn deinit(self: *MatchTelemetry) void {
        for (self.entities_array[0..self.entities_count]) |*entity_stat| {
            entity_stat.deinit();
        }
        self.school_matchups.deinit();
    }

    /// Register an entity for tracking
    pub fn registerEntity(self: *MatchTelemetry, entity_id: u32, name: []const u8, school: []const u8, position: []const u8, team: u8, is_player: bool) !void {
        if (self.entities_count >= 8) return;
        const stats = try EntityStats.init(self.allocator, entity_id, name, school, position, team, is_player);
        self.entities_array[self.entities_count] = stats;
        self.entities_count += 1;
    }

    /// Get entity stats by ID
    pub fn getEntityStats(self: *MatchTelemetry, entity_id: u32) ?*EntityStats {
        for (self.entities_array[0..self.entities_count]) |*stat| {
            if (stat.entity_id == entity_id) {
                return stat;
            }
        }
        return null;
    }

    /// Get entity stats by ID (const version)
    pub fn getEntityStatsConst(self: *const MatchTelemetry, entity_id: u32) ?*const EntityStats {
        for (self.entities_array[0..self.entities_count]) |*stat| {
            if (stat.entity_id == entity_id) {
                return stat;
            }
        }
        return null;
    }

    /// Record damage dealt
    pub fn recordDamage(self: *MatchTelemetry, attacker_id: u32, defender_id: u32, raw_damage: f32, armor: f32, damage_type: []const u8) void {
        if (self.getEntityStats(attacker_id)) |attacker_stat| {
            const effective_damage = attacker_stat.calcEffectiveDamage(raw_damage, armor);
            attacker_stat.damage_dealt += effective_damage;

            if (attacker_stat.team == 0) {
                self.total_damage_dealt_ally += effective_damage;
            } else {
                self.total_damage_dealt_enemy += effective_damage;
            }
        }

        if (self.getEntityStats(defender_id)) |defender_stat| {
            defender_stat.damage_received += raw_damage;
        }

        _ = damage_type; // For future use (physical, elemental, etc)
    }

    /// Record healing dealt
    pub fn recordHealing(self: *MatchTelemetry, healer_id: u32, target_id: u32, amount: f32, was_overhealing: bool) void {
        if (self.getEntityStats(healer_id)) |healer_stat| {
            healer_stat.healing_dealt += amount;

            if (healer_stat.team == 0) {
                self.total_healing_ally += amount;
            } else {
                self.total_healing_enemy += amount;
            }
        }

        if (self.getEntityStats(target_id)) |target_stat| {
            target_stat.healing_received += amount;
            if (was_overhealing) {
                target_stat.overhealing += amount;
            }
        }
    }

    /// Record skill cast
    pub fn recordSkillCast(self: *MatchTelemetry, caster_id: u32, skill_name: []const u8, energy_cost: f32, success: bool) void {
        if (self.getEntityStats(caster_id)) |caster_stat| {
            caster_stat.energy_spent += energy_cost;

            if (success) {
                caster_stat.skills_cast += 1;
            } else {
                caster_stat.skills_failed += 1;
            }

            // Record per-skill stats
            var skill_stat = caster_stat.skill_usage.getOrPut(skill_name) catch |err| {
                print("Error recording skill stat: {}\n", .{err});
                return;
            };

            if (skill_stat.found_existing) {
                if (success) {
                    skill_stat.value_ptr.casts += 1;
                } else {
                    skill_stat.value_ptr.failures += 1;
                }
            } else {
                var new_stat = SkillStats.init(self.allocator, skill_name) catch {
                    return;
                };
                new_stat.casts = if (success) 1 else 0;
                new_stat.failures = if (success) 0 else 1;
                new_stat.total_energy_cost = energy_cost;
                skill_stat.value_ptr.* = new_stat;
            }

            skill_stat.value_ptr.total_energy_cost += energy_cost;
        }
    }

    /// Record damage from a specific skill
    pub fn recordSkillDamage(self: *MatchTelemetry, caster_id: u32, skill_name: []const u8, damage: f32) void {
        if (self.getEntityStats(caster_id)) |caster_stat| {
            if (caster_stat.skill_usage.getPtr(skill_name)) |skill_stat| {
                skill_stat.recordDamage(damage);
            }
        }
    }

    /// Record healing from a specific skill
    pub fn recordSkillHealing(self: *MatchTelemetry, caster_id: u32, skill_name: []const u8, healing: f32, overhealing: f32) void {
        if (self.getEntityStats(caster_id)) |caster_stat| {
            if (caster_stat.skill_usage.getPtr(skill_name)) |skill_stat| {
                skill_stat.recordHealing(healing, overhealing);
            }
        }
    }

    /// Record a condition applied by a specific skill
    pub fn recordSkillCondition(self: *MatchTelemetry, caster_id: u32, skill_name: []const u8, condition_name: []const u8) void {
        if (self.getEntityStats(caster_id)) |caster_stat| {
            if (caster_stat.skill_usage.getPtr(skill_name)) |skill_stat| {
                skill_stat.conditions_applied += 1;
                const cond_count = skill_stat.conditions_map.getOrPut(condition_name) catch {
                    return;
                };
                if (cond_count.found_existing) {
                    cond_count.value_ptr.* += 1;
                } else {
                    cond_count.value_ptr.* = 1;
                }
            }
        }
    }

    /// Record entity death
    pub fn recordDeath(self: *MatchTelemetry, entity_id: u32) void {
        if (self.getEntityStats(entity_id)) |entity_stat| {
            entity_stat.deaths += 1;
        }
    }

    /// Record entity kill
    pub fn recordKill(self: *MatchTelemetry, killer_id: u32) void {
        if (self.getEntityStats(killer_id)) |killer_stat| {
            killer_stat.kills += 1;
        }
    }

    /// Record condition applied
    pub fn recordCondition(self: *MatchTelemetry, applier_id: u32, condition_type: []const u8) void {
        if (self.getEntityStats(applier_id)) |applier_stat| {
            applier_stat.conditions_applied += 1;
        }
        _ = condition_type; // For future breakdown by condition type
    }

    // ===== AI DECISION TRACKING =====

    pub fn recordTargetAcquisition(self: *MatchTelemetry, entity_id: u32) void {
        if (self.getEntityStats(entity_id)) |stats| {
            stats.target_acquisitions += 1;
        }
    }

    pub fn recordCastingAttempt(self: *MatchTelemetry, entity_id: u32) void {
        if (self.getEntityStats(entity_id)) |stats| {
            stats.casting_attempts += 1;
        }
    }

    pub fn recordNoEnergyBlock(self: *MatchTelemetry, entity_id: u32) void {
        if (self.getEntityStats(entity_id)) |stats| {
            stats.no_energy_blocks += 1;
        }
    }

    pub fn recordOutOfRangeBlock(self: *MatchTelemetry, entity_id: u32) void {
        if (self.getEntityStats(entity_id)) |stats| {
            stats.out_of_range_blocks += 1;
        }
    }

    pub fn recordCooldownBlock(self: *MatchTelemetry, entity_id: u32) void {
        if (self.getEntityStats(entity_id)) |stats| {
            stats.cooldown_blocks += 1;
        }
    }

    pub fn recordQueueSkillCall(self: *MatchTelemetry, entity_id: u32) void {
        if (self.getEntityStats(entity_id)) |stats| {
            stats.queue_skill_calls += 1;
        }
    }

    pub fn recordExecuteQueueCall(self: *MatchTelemetry, entity_id: u32) void {
        if (self.getEntityStats(entity_id)) |stats| {
            stats.execute_queue_calls += 1;
        }
    }

    pub fn recordExecuteQueueSuccess(self: *MatchTelemetry, entity_id: u32) void {
        if (self.getEntityStats(entity_id)) |stats| {
            stats.execute_queue_success += 1;
        }
    }

    pub fn recordExecuteQueueOutOfRange(self: *MatchTelemetry, entity_id: u32) void {
        if (self.getEntityStats(entity_id)) |stats| {
            stats.execute_queue_out_of_range += 1;
        }
    }

    pub fn recordExecuteQueueNoEnergy(self: *MatchTelemetry, entity_id: u32) void {
        if (self.getEntityStats(entity_id)) |stats| {
            stats.execute_queue_no_energy += 1;
        }
    }

    pub fn recordConditionFails(self: *MatchTelemetry, entity_id: u32) void {
        if (self.getEntityStats(entity_id)) |stats| {
            stats.condition_fails += 1;
        }
    }

    pub fn recordCastingAttempts(self: *MatchTelemetry, entity_id: u32) void {
        if (self.getEntityStats(entity_id)) |stats| {
            stats.casting_attempts += 1;
        }
    }

    pub fn recordExecuteQueueTargetDead(self: *MatchTelemetry, entity_id: u32) void {
        if (self.getEntityStats(entity_id)) |stats| {
            stats.execute_queue_target_dead += 1;
        }
    }

    pub fn recordNoValidTargetBlock(self: *MatchTelemetry, entity_id: u32) void {
        if (self.getEntityStats(entity_id)) |stats| {
            stats.no_valid_target_blocks += 1;
        }
    }

    pub fn recordConditionFail(self: *MatchTelemetry, entity_id: u32) void {
        if (self.getEntityStats(entity_id)) |stats| {
            stats.condition_fails += 1;
        }
    }

    pub fn recordMovementAttempt(self: *MatchTelemetry, entity_id: u32) void {
        if (self.getEntityStats(entity_id)) |stats| {
            stats.movement_attempts += 1;
        }
    }

    pub fn recordIdleTick(self: *MatchTelemetry, entity_id: u32) void {
        if (self.getEntityStats(entity_id)) |stats| {
            stats.idle_ticks += 1;
        }
    }

    pub fn recordTargetIdSet(self: *MatchTelemetry, entity_id: u32) void {
        if (self.getEntityStats(entity_id)) |stats| {
            stats.target_id_set += 1;
        }
    }

    pub fn recordTargetIdNone(self: *MatchTelemetry, entity_id: u32) void {
        if (self.getEntityStats(entity_id)) |stats| {
            stats.target_id_none += 1;
        }
    }

    pub fn recordMovement(self: *MatchTelemetry, entity_id: u32, distance: f32, is_forward: bool) void {
        if (self.getEntityStats(entity_id)) |stats| {
            stats.total_distance_moved += distance;
            if (is_forward) {
                stats.forward_movement_attempts += 1;
            }
        }
    }

    pub fn recordMovementVector(self: *MatchTelemetry, entity_id: u32, move_x: f32, move_z: f32) void {
        if (self.getEntityStats(entity_id)) |stats| {
            stats.movement_vectors_sum_x += move_x;
            stats.movement_vectors_sum_z += move_z;
        }
    }

    /// Record position metrics for range efficiency analysis
    pub fn recordPositionMetrics(self: *MatchTelemetry, entity_id: u32, distance_to_target: f32, in_optimal_range: bool, position_role: []const u8) void {
        if (self.getEntityStats(entity_id)) |stats| {
            stats.position_metrics.effective_range = distance_to_target;

            if (in_optimal_range) {
                stats.position_metrics.time_in_optimal_range += 1;
            } else {
                stats.position_metrics.time_out_of_optimal_range += 1;
            }

            _ = position_role; // For future use (melee/ranged/support specific logic)
        }
    }

    // ===== TIMELINE & MATCHUP TRACKING =====

    /// Add an event to the timeline
    pub fn recordTimelineEvent(self: *MatchTelemetry, event: TimelineEvent) void {
        if (self.timeline_count < self.timeline_events.len) {
            self.timeline_events[self.timeline_count] = event;
            self.timeline_count += 1;
        }
    }

    /// Record school matchup data for balance analysis
    pub fn recordSchoolMatchup(self: *MatchTelemetry, attacker_school: []const u8, defender_school: []const u8, damage: f32, kills: u32, deaths: u32, won: bool) void {
        var key: [512]u8 = undefined;
        const key_str = std.fmt.bufPrint(&key, "{s}_vs_{s}", .{ attacker_school, defender_school }) catch return;

        var matchup = self.school_matchups.getOrPut(key_str) catch return;
        if (!matchup.found_existing) {
            matchup.value_ptr.* = .{};
        }

        matchup.value_ptr.total_damage += damage;
        matchup.value_ptr.total_kills += kills;
        matchup.value_ptr.total_deaths += deaths;
        matchup.value_ptr.matches += 1;
        if (won) {
            matchup.value_ptr.wins += 1;
        }
    }

    /// Analyze timeline to get match phases (early game, mid game, late game)
    pub fn getMatchPhases(self: *const MatchTelemetry) PhaseAnalysis {
        var analysis: PhaseAnalysis = .{};

        const total_ticks = self.match_duration_ticks;
        const early_end = total_ticks / 3;
        const mid_end = (2 * total_ticks) / 3;

        var ally_damage: [3]f32 = .{ 0, 0, 0 };
        var enemy_damage: [3]f32 = .{ 0, 0, 0 };

        for (self.timeline_events[0..self.timeline_count]) |event| {
            if (event.event_type != .damage_dealt) continue;

            const phase: u32 = if (event.tick < early_end) 0 else if (event.tick < mid_end) 1 else 2;

            if (self.getEntityStatsConst(event.entity_id)) |entity| {
                if (entity.team == 0) {
                    ally_damage[phase] += event.data.damage.amount;
                } else {
                    enemy_damage[phase] += event.data.damage.amount;
                }
            }
        }

        analysis.early_game = .{ .ally_damage = ally_damage[0], .enemy_damage = enemy_damage[0] };
        analysis.mid_game = .{ .ally_damage = ally_damage[1], .enemy_damage = enemy_damage[1] };
        analysis.late_game = .{ .ally_damage = ally_damage[2], .enemy_damage = enemy_damage[2] };

        return analysis;
    }

    pub const PhaseAnalysis = struct {
        early_game: PhaseStats = .{},
        mid_game: PhaseStats = .{},
        late_game: PhaseStats = .{},

        pub const PhaseStats = struct {
            ally_damage: f32 = 0.0,
            enemy_damage: f32 = 0.0,

            pub fn getDominance(self: PhaseStats) f32 {
                const total = self.ally_damage + self.enemy_damage;
                if (total == 0) return 0.0;
                return self.ally_damage / total;
            }
        };
    };

    /// Print match summary
    pub fn printSummary(self: *const MatchTelemetry) void {
        print("\n=== MATCH TELEMETRY REPORT ===\n", .{});
        print("Duration: {} ticks\n", .{self.match_duration_ticks});

        if (self.winning_team) |team| {
            const team_name = if (team == 0) "ALLY" else "ENEMY";
            print("Winner: {s} TEAM\n", .{team_name});
        }

        print("\n--- TEAM SUMMARY ---\n", .{});
        print("Ally Team - Damage: {d:.1}, Healing: {d:.1}\n", .{ self.total_damage_dealt_ally, self.total_healing_ally });
        print("Enemy Team - Damage: {d:.1}, Healing: {d:.1}\n", .{ self.total_damage_dealt_enemy, self.total_healing_enemy });

        print("\n--- PER-ENTITY BREAKDOWN ---\n", .{});
        for (self.entities_array[0..self.entities_count]) |entity_stat| {
            const team_name = if (entity_stat.team == 0) "ALLY" else "ENMY";
            print("\n{s} #{d}: {s} ({s}/{s})\n", .{ team_name, entity_stat.entity_id, entity_stat.name, entity_stat.school, entity_stat.position });
            print("  HP Status: {d} kills, {d} deaths\n", .{ entity_stat.kills, entity_stat.deaths });
            print("  Damage: {d:.1} dealt / {d:.1} received (efficiency: {d:.1}%)\n", .{ entity_stat.damage_dealt, entity_stat.damage_received, entity_stat.calcEfficiency() * 100.0 });
            print("  Healing: {d:.1} dealt / {d:.1} received (overhealing: {d:.1})\n", .{ entity_stat.healing_dealt, entity_stat.healing_received, entity_stat.overhealing });
            print("  Skills: {d} cast, {d} failed (success rate: {d:.1}%)\n", .{ entity_stat.skills_cast, entity_stat.skills_failed, entity_stat.getSkillSuccessRate() * 100.0 });
            print("  Energy: {d:.1} spent, {d:.1} regenerated\n", .{ entity_stat.energy_spent, entity_stat.energy_regenerated });
            print("  DPS: {d:.1}\n", .{entity_stat.calcDPS()});

            // Position metrics
            print("  Position Efficiency: Range: {d:.1}m, Optimal time: {d:.1}%\n", .{ entity_stat.position_metrics.effective_range, entity_stat.position_metrics.calcRangeEfficiency() * 100.0 });

            // AI Decision Tracking
            print("  AI Activity: Cast Rate: {d:.3} casts/tick, Inactivity: {d:.1}%\n", .{ entity_stat.getCastRate(), entity_stat.getInactivityRate() * 100.0 });
            print("    Targets found: {d}, Casting attempts: {d}\n", .{ entity_stat.target_acquisitions, entity_stat.casting_attempts });
            print("    Movement: Distance: {d:.1}m, Forward moves: {d}, Attempts: {d}\n", .{ entity_stat.total_distance_moved, entity_stat.forward_movement_attempts, entity_stat.movement_attempts });
            print("    Movement vectors: Sum X={d:.1}, Sum Z={d:.1}\n", .{ entity_stat.movement_vectors_sum_x, entity_stat.movement_vectors_sum_z });
            print("    Blocks - Energy: {d}, Range: {d}, Cooldown: {d}, NoTarget: {d}, Conditions: {d}\n", .{
                entity_stat.no_energy_blocks,
                entity_stat.out_of_range_blocks,
                entity_stat.cooldown_blocks,
                entity_stat.no_valid_target_blocks,
                entity_stat.condition_fails,
            });
            print("    Main blockage: {s}\n", .{entity_stat.getMainBlockageReason()});

            // Skill breakdown
            if (entity_stat.skill_usage.count() > 0) {
                print("  Top Skills:\n", .{});
                var skill_it = entity_stat.skill_usage.iterator();
                while (skill_it.next()) |entry| {
                    const skill_stat = entry.value_ptr;
                    print("    {s}: {d} casts, {d:.1} damage, {d:.1} healing (success: {d:.1}%)\n", .{
                        skill_stat.skill_name,
                        skill_stat.casts,
                        skill_stat.total_damage,
                        skill_stat.total_healing,
                        skill_stat.getSuccessRate() * 100.0,
                    });
                }
            }
        }

        // Match phases
        const phases = self.getMatchPhases();
        print("\n--- MATCH PHASES ---\n", .{});
        print("Early Game: Allies {d:.0}dmg vs Enemies {d:.0}dmg (Dominance: {d:.1}%)\n", .{
            phases.early_game.ally_damage,
            phases.early_game.enemy_damage,
            phases.early_game.getDominance() * 100.0,
        });
        print("Mid Game: Allies {d:.0}dmg vs Enemies {d:.0}dmg (Dominance: {d:.1}%)\n", .{
            phases.mid_game.ally_damage,
            phases.mid_game.enemy_damage,
            phases.mid_game.getDominance() * 100.0,
        });
        print("Late Game: Allies {d:.0}dmg vs Enemies {d:.0}dmg (Dominance: {d:.1}%)\n", .{
            phases.late_game.ally_damage,
            phases.late_game.enemy_damage,
            phases.late_game.getDominance() * 100.0,
        });
    }

    /// Export as structured report (for analysis)
    pub fn exportJSON(self: *const MatchTelemetry, _: std.mem.Allocator, filepath: []const u8) !void {
        var file = try std.fs.cwd().createFile(filepath, .{});
        defer file.close();

        var json: [262144]u8 = undefined; // Increased buffer for per-skill stats
        var stream = std.io.fixedBufferStream(&json);
        var writer = stream.writer();

        try writer.writeAll("{\n");
        try writer.print("  \"match_duration_ticks\": {d},\n", .{self.match_duration_ticks});
        try writer.print("  \"winning_team\": {d},\n", .{if (self.winning_team) |t| t else 255});
        try writer.print("  \"total_damage_dealt_ally\": {d},\n", .{self.total_damage_dealt_ally});
        try writer.print("  \"total_damage_dealt_enemy\": {d},\n", .{self.total_damage_dealt_enemy});
        try writer.print("  \"total_healing_ally\": {d},\n", .{self.total_healing_ally});
        try writer.print("  \"total_healing_enemy\": {d},\n", .{self.total_healing_enemy});

        // Add match phases
        const phases = self.getMatchPhases();
        try writer.writeAll("  \"match_phases\": {\n");
        try writer.print("    \"early_game\": {{\"ally_damage\": {d}, \"enemy_damage\": {d}, \"ally_dominance\": {d}}},\n", .{
            phases.early_game.ally_damage,
            phases.early_game.enemy_damage,
            phases.early_game.getDominance(),
        });
        try writer.print("    \"mid_game\": {{\"ally_damage\": {d}, \"enemy_damage\": {d}, \"ally_dominance\": {d}}},\n", .{
            phases.mid_game.ally_damage,
            phases.mid_game.enemy_damage,
            phases.mid_game.getDominance(),
        });
        try writer.print("    \"late_game\": {{\"ally_damage\": {d}, \"enemy_damage\": {d}, \"ally_dominance\": {d}}}\n", .{
            phases.late_game.ally_damage,
            phases.late_game.enemy_damage,
            phases.late_game.getDominance(),
        });
        try writer.writeAll("  },\n");

        try writer.writeAll("  \"entities\": [\n");

        for (self.entities_array[0..self.entities_count], 0..) |entity_stat, i| {
            try writer.writeAll("    {\n");
            try writer.print("      \"entity_id\": {d},\n", .{entity_stat.entity_id});
            try writer.print("      \"name\": \"{s}\",\n", .{entity_stat.name});
            try writer.print("      \"school\": \"{s}\",\n", .{entity_stat.school});
            try writer.print("      \"position\": \"{s}\",\n", .{entity_stat.position});
            try writer.print("      \"team\": {d},\n", .{entity_stat.team});
            try writer.print("      \"damage_dealt\": {d},\n", .{entity_stat.damage_dealt});
            try writer.print("      \"damage_received\": {d},\n", .{entity_stat.damage_received});
            try writer.print("      \"healing_dealt\": {d},\n", .{entity_stat.healing_dealt});
            try writer.print("      \"healing_received\": {d},\n", .{entity_stat.healing_received});
            try writer.print("      \"kills\": {d},\n", .{entity_stat.kills});
            try writer.print("      \"deaths\": {d},\n", .{entity_stat.deaths});
            try writer.print("      \"skills_cast\": {d},\n", .{entity_stat.skills_cast});
            try writer.print("      \"skills_failed\": {d},\n", .{entity_stat.skills_failed});
            try writer.print("      \"efficiency\": {d},\n", .{entity_stat.calcEfficiency()});
            try writer.print("      \"cast_rate\": {d},\n", .{entity_stat.getCastRate()});
            try writer.print("      \"inactivity_rate\": {d},\n", .{entity_stat.getInactivityRate()});
            try writer.print("      \"target_acquisitions\": {d},\n", .{entity_stat.target_acquisitions});
            try writer.print("      \"casting_attempts\": {d},\n", .{entity_stat.casting_attempts});
            try writer.print("      \"no_energy_blocks\": {d},\n", .{entity_stat.no_energy_blocks});
            try writer.print("      \"out_of_range_blocks\": {d},\n", .{entity_stat.out_of_range_blocks});
            try writer.print("      \"cooldown_blocks\": {d},\n", .{entity_stat.cooldown_blocks});
            try writer.print("      \"no_valid_target_blocks\": {d},\n", .{entity_stat.no_valid_target_blocks});
            try writer.print("      \"condition_fails\": {d},\n", .{entity_stat.condition_fails});
            try writer.print("      \"movement_attempts\": {d},\n", .{entity_stat.movement_attempts});
            try writer.print("      \"total_distance_moved\": {d},\n", .{entity_stat.total_distance_moved});
            try writer.print("      \"forward_movement_attempts\": {d},\n", .{entity_stat.forward_movement_attempts});
            try writer.print("      \"idle_ticks\": {d},\n", .{entity_stat.idle_ticks});

            // Queue debugging
            try writer.print("      \"queue_skill_calls\": {d},\n", .{entity_stat.queue_skill_calls});
            try writer.print("      \"execute_queue_calls\": {d},\n", .{entity_stat.execute_queue_calls});
            try writer.print("      \"execute_queue_success\": {d},\n", .{entity_stat.execute_queue_success});
            try writer.print("      \"execute_queue_out_of_range\": {d},\n", .{entity_stat.execute_queue_out_of_range});
            try writer.print("      \"execute_queue_no_energy\": {d},\n", .{entity_stat.execute_queue_no_energy});
            try writer.print("      \"execute_queue_target_dead\": {d},\n", .{entity_stat.execute_queue_target_dead});

            // Position metrics
            try writer.print("      \"position_metrics\": {{\n", .{});
            try writer.print("        \"effective_range\": {d},\n", .{entity_stat.position_metrics.effective_range});
            try writer.print("        \"time_in_optimal_range\": {d},\n", .{entity_stat.position_metrics.time_in_optimal_range});
            try writer.print("        \"range_efficiency\": {d}\n", .{entity_stat.position_metrics.calcRangeEfficiency()});
            try writer.print("      }},\n", .{});

            // Per-skill breakdown
            if (entity_stat.skill_usage.count() > 0) {
                try writer.writeAll("      \"skills\": [\n");
                var skill_it = entity_stat.skill_usage.iterator();
                var skill_count: u32 = 0;
                while (skill_it.next()) |entry| {
                    const skill_stat = entry.value_ptr;
                    try writer.writeAll("        {\n");
                    try writer.print("          \"name\": \"{s}\",\n", .{skill_stat.skill_name});
                    try writer.print("          \"casts\": {d},\n", .{skill_stat.casts});
                    try writer.print("          \"failures\": {d},\n", .{skill_stat.failures});
                    try writer.print("          \"success_rate\": {d},\n", .{skill_stat.getSuccessRate()});
                    try writer.print("          \"total_damage\": {d},\n", .{skill_stat.total_damage});
                    try writer.print("          \"min_damage\": {d},\n", .{skill_stat.min_damage});
                    try writer.print("          \"max_damage\": {d},\n", .{skill_stat.max_damage});
                    try writer.print("          \"avg_damage\": {d},\n", .{skill_stat.getAverageDamage()});
                    try writer.print("          \"damage_hits\": {d},\n", .{skill_stat.damage_hits});
                    try writer.print("          \"total_healing\": {d},\n", .{skill_stat.total_healing});
                    try writer.print("          \"total_overhealing\": {d},\n", .{skill_stat.total_overhealing});
                    try writer.print("          \"healing_hits\": {d},\n", .{skill_stat.healing_hits});
                    try writer.print("          \"energy_cost\": {d},\n", .{skill_stat.total_energy_cost});
                    try writer.print("          \"conditions_applied\": {d}\n", .{skill_stat.conditions_applied});
                    try writer.writeAll("        }");
                    skill_count += 1;
                    // Note: We can't easily iterate again, so we'll just close without trailing comma
                    if (skill_count < entity_stat.skill_usage.count()) {
                        try writer.writeAll(",");
                    }
                    try writer.writeAll("\n");
                }
                try writer.writeAll("      ],\n");
            }

            try writer.print("      \"main_blockage\": \"{s}\"\n", .{entity_stat.getMainBlockageReason()});
            try writer.writeAll("    }");

            if (i < self.entities_count - 1) {
                try writer.writeAll(",");
            }
            try writer.writeAll("\n");
        }

        try writer.writeAll("  ]\n");
        try writer.writeAll("}\n");

        _ = try file.writeAll(stream.getWritten());
    }
};

/// Analyze school performance across multiple matches
pub const SchoolPerformanceAnalysis = struct {
    allocator: std.mem.Allocator,
    school_stats: std.StringHashMap(SchoolStats) = undefined,

    pub const SchoolStats = struct {
        total_damage: f32 = 0.0,
        total_healing: f32 = 0.0,
        total_kills: u32 = 0,
        total_deaths: u32 = 0,
        matches_played: u32 = 0,
        win_count: u32 = 0,

        pub fn getWinRate(self: *const SchoolStats) f32 {
            if (self.matches_played == 0) return 0.0;
            return @as(f32, @floatFromInt(self.win_count)) / @as(f32, @floatFromInt(self.matches_played));
        }

        pub fn getKDRatio(self: *const SchoolStats) f32 {
            if (self.total_deaths == 0) return @as(f32, @floatFromInt(self.total_kills));
            return @as(f32, @floatFromInt(self.total_kills)) / @as(f32, @floatFromInt(self.total_deaths));
        }
    };

    pub fn init(allocator: std.mem.Allocator) !SchoolPerformanceAnalysis {
        return .{
            .allocator = allocator,
            .school_stats = std.StringHashMap(SchoolStats).init(allocator),
        };
    }

    pub fn deinit(self: *SchoolPerformanceAnalysis) void {
        self.school_stats.deinit();
    }

    pub fn analyzeMatch(self: *SchoolPerformanceAnalysis, telemetry: *const MatchTelemetry) !void {
        for (telemetry.entities_array[0..telemetry.entities_count]) |entity_stat| {
            var school_stat = try self.school_stats.getOrPut(entity_stat.school);

            if (!school_stat.found_existing) {
                school_stat.value_ptr.* = .{};
            }

            school_stat.value_ptr.total_damage += entity_stat.damage_dealt;
            school_stat.value_ptr.total_healing += entity_stat.healing_dealt;
            school_stat.value_ptr.total_kills += entity_stat.kills;
            school_stat.value_ptr.total_deaths += entity_stat.deaths;
            school_stat.value_ptr.matches_played += 1;

            if (telemetry.winning_team) |winning_team| {
                if (winning_team == entity_stat.team) {
                    school_stat.value_ptr.win_count += 1;
                }
            }
        }
    }

    pub fn printAnalysis(self: *const SchoolPerformanceAnalysis) void {
        print("\n=== SCHOOL PERFORMANCE ANALYSIS ===\n", .{});
        var it = self.school_stats.iterator();
        while (it.next()) |entry| {
            const school = entry.key_ptr.*;
            const stats = entry.value_ptr.*;
            print("{s}: {d} matches, {d:.1}% winrate, K/D {d:.2}, DMG {d:.0}, HEAL {d:.0}\n", .{
                school,
                stats.matches_played,
                stats.getWinRate() * 100.0,
                stats.getKDRatio(),
                stats.total_damage,
                stats.total_healing,
            });
        }
    }
};
