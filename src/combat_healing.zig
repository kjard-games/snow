const std = @import("std");
const rl = @import("raylib");
const character = @import("character.zig");
const skills = @import("skills.zig");
const vfx = @import("vfx.zig");
const telemetry = @import("telemetry.zig");

const Character = character.Character;
const Skill = skills.Skill;
const MatchTelemetry = telemetry.MatchTelemetry;
const print = std.debug.print;

// ============================================================================
// COMBAT HEALING - Healing calculation and application
// ============================================================================
// This module handles all healing mechanics:
// - Base healing from skills
// - Healing modifiers (Hot Cocoa buff)
// - Overheal detection (for telemetry)
// - VFX spawning
//
// Design: Separating healing allows for:
// - Consistent healing formula across all sources
// - Easy addition of new healing modifiers
// - Clear tracking of healing vs overhealing

// ============================================================================
// HEALING RESULT - Outcome of healing calculation
// ============================================================================

pub const HealingResult = struct {
    /// Amount of healing applied (clamped to max health)
    healing_applied: f32,
    /// Raw healing amount before clamping
    raw_healing: f32,
    /// Whether any healing was wasted (overheal)
    was_overhealing: bool,
    /// Amount of healing wasted
    overheal_amount: f32,
};

// ============================================================================
// HEALING MODIFIERS
// ============================================================================

/// Calculate healing multiplier from target's buffs
pub fn calculateHealingMultiplier(target: *const Character) f32 {
    var multiplier: f32 = 1.0;

    // Hot Cocoa buff increases healing received
    if (target.hasCozy(.hot_cocoa)) {
        multiplier *= 1.5; // 50% increased healing
    }

    // Future: Add more healing modifiers here
    // - Chill debuff that reduces healing received
    // - Effect that increases healing based on missing health
    // - etc.

    return multiplier;
}

// ============================================================================
// MAIN HEALING FUNCTIONS
// ============================================================================

/// Calculate and apply healing to a target
/// Returns details about the healing applied
pub fn applyHealing(
    caster: *Character,
    target: *Character,
    base_healing: f32,
    vfx_manager: *vfx.VFXManager,
    telem: ?*MatchTelemetry,
) HealingResult {
    // Calculate modified healing
    const multiplier = calculateHealingMultiplier(target);
    const raw_healing = base_healing * multiplier;

    // Track previous health for overheal detection
    const prev_hp = target.stats.warmth;

    // Apply healing (clamped to max)
    target.stats.warmth = @min(target.stats.max_warmth, target.stats.warmth + raw_healing);

    // Calculate actual healing applied
    const healing_applied = target.stats.warmth - prev_hp;
    const was_overhealing = raw_healing > healing_applied;
    const overheal_amount = if (was_overhealing) raw_healing - healing_applied else 0;

    // Record telemetry
    if (telem) |tel| {
        tel.recordHealing(caster.id, target.id, raw_healing, was_overhealing);
    }

    // Spawn VFX
    vfx_manager.spawnHeal(target.position);
    vfx_manager.spawnDamageNumber(raw_healing, target.position, .heal);

    // Log
    print("{s} healed {s} for {d:.1}! ({d:.1}/{d:.1} HP)\n", .{
        caster.name,
        target.name,
        raw_healing,
        target.stats.warmth,
        target.stats.max_warmth,
    });

    return HealingResult{
        .healing_applied = healing_applied,
        .raw_healing = raw_healing,
        .was_overhealing = was_overhealing,
        .overheal_amount = overheal_amount,
    };
}

/// Apply self-healing (simplified version for self-targeted skills)
pub fn applySelfHealing(
    caster: *Character,
    base_healing: f32,
    vfx_manager: *vfx.VFXManager,
) HealingResult {
    // Calculate modified healing
    const multiplier = calculateHealingMultiplier(caster);
    const raw_healing = base_healing * multiplier;

    // Track previous health
    const prev_hp = caster.stats.warmth;

    // Apply healing
    caster.stats.warmth = @min(caster.stats.max_warmth, caster.stats.warmth + raw_healing);

    // Calculate actual healing
    const healing_applied = caster.stats.warmth - prev_hp;
    const was_overhealing = raw_healing > healing_applied;
    const overheal_amount = if (was_overhealing) raw_healing - healing_applied else 0;

    // Spawn VFX
    vfx_manager.spawnHeal(caster.position);
    vfx_manager.spawnDamageNumber(raw_healing, caster.position, .heal);

    // Log
    print("{s} healed self for {d:.1}!\n", .{ caster.name, raw_healing });

    return HealingResult{
        .healing_applied = healing_applied,
        .raw_healing = raw_healing,
        .was_overhealing = was_overhealing,
        .overheal_amount = overheal_amount,
    };
}

/// Calculate expected healing without applying it (for UI preview)
pub fn previewHealing(target: *const Character, base_healing: f32) struct { expected: f32, would_overheal: bool } {
    const multiplier = calculateHealingMultiplier(target);
    const raw_healing = base_healing * multiplier;

    const potential_hp = target.stats.warmth + raw_healing;
    const would_overheal = potential_hp > target.stats.max_warmth;

    return .{
        .expected = raw_healing,
        .would_overheal = would_overheal,
    };
}

// ============================================================================
// TESTS
// ============================================================================

test "healing multiplier without buffs" {
    // Would need Character setup
    // Base multiplier should be 1.0
}

test "hot cocoa healing boost" {
    // Would need Character setup
    // With Hot Cocoa, multiplier should be 1.5
}
