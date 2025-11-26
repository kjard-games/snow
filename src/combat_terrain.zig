const std = @import("std");
const rl = @import("raylib");
const character = @import("character.zig");
const skills = @import("skills.zig");
const terrain_mod = @import("terrain.zig");

const Character = character.Character;
const Skill = skills.Skill;
const TerrainGrid = terrain_mod.TerrainGrid;
const print = std.debug.print;

// ============================================================================
// COMBAT TERRAIN - Terrain manipulation during combat
// ============================================================================
// This module handles all terrain effects from skills:
// - Building walls (snow walls, ice walls)
// - Creating terrain patches (fire, ice, mud)
// - Destroying walls in an area
// - Applying terrain shapes (circle, cone, line, etc.)
//
// Design: Separating terrain effects allows for:
// - Clear terrain modification logic
// - Consistent terrain application across skills
// - Easy addition of new terrain types and shapes

// ============================================================================
// TERRAIN EFFECT APPLICATION
// ============================================================================

/// Apply a terrain effect with the specified shape
pub fn applyTerrainShape(
    terrain_grid: *TerrainGrid,
    effect: skills.TerrainEffect,
    center_x: f32,
    center_z: f32,
    radius: f32,
    caster_pos: ?rl.Vector3,
) void {
    const terrain_type = effect.terrain_type orelse return;

    switch (effect.shape) {
        .none => {},
        .circle => {
            terrain_grid.setTerrainInRadius(center_x, center_z, radius, terrain_type);
            print("  -> Created {s} circle (radius {d:.1})\n", .{ @tagName(terrain_type), radius });
        },
        .cone => {
            // TODO: Implement cone shape (from caster toward target)
            // For now, use circle as fallback
            terrain_grid.setTerrainInRadius(center_x, center_z, radius, terrain_type);
            print("  -> Created {s} cone (radius {d:.1})\n", .{ @tagName(terrain_type), radius });
        },
        .line => {
            // TODO: Implement line shape (from caster to target)
            if (caster_pos) |cpos| {
                // Line from caster to target position
                _ = cpos;
                terrain_grid.setTerrainInRadius(center_x, center_z, radius, terrain_type);
            } else {
                terrain_grid.setTerrainInRadius(center_x, center_z, radius, terrain_type);
            }
            print("  -> Created {s} line (radius {d:.1})\n", .{ @tagName(terrain_type), radius });
        },
        .ring => {
            // TODO: Implement ring shape (donut - terrain only at outer edge)
            terrain_grid.setTerrainInRadius(center_x, center_z, radius, terrain_type);
            print("  -> Created {s} ring (radius {d:.1})\n", .{ @tagName(terrain_type), radius });
        },
        .trail => {
            // Trails are created during movement, not on cast
            // This is handled by the movement system
            print("  -> Enabled {s} trail effect\n", .{@tagName(terrain_type)});
        },
        .square => {
            // TODO: Implement square shape
            terrain_grid.setTerrainInRadius(center_x, center_z, radius, terrain_type);
            print("  -> Created {s} square (radius {d:.1})\n", .{ @tagName(terrain_type), radius });
        },
        .cross => {
            // TODO: Implement cross shape
            terrain_grid.setTerrainInRadius(center_x, center_z, radius, terrain_type);
            print("  -> Created {s} cross (radius {d:.1})\n", .{ @tagName(terrain_type), radius });
        },
    }
}

// ============================================================================
// WALL BUILDING
// ============================================================================

/// Build a wall from a skill at a ground position
/// Wall is placed perpendicular to the caster->target direction
pub fn buildWallAtPosition(
    terrain_grid: *TerrainGrid,
    skill: *const Skill,
    caster: *const Character,
    ground_pos: rl.Vector3,
) void {
    if (!skill.creates_wall) return;

    // Calculate facing angle from caster to ground position
    const dx = ground_pos.x - caster.position.x;
    const dz = ground_pos.z - caster.position.z;
    const facing_angle = std.math.atan2(dz, dx);

    // Build wall centered at ground_pos, perpendicular to the caster->target direction
    terrain_grid.buildWallPerpendicular(
        ground_pos.x,
        ground_pos.z,
        facing_angle,
        0.0, // No offset - wall is centered at ground_pos
        skill.wall_length,
        skill.wall_height,
        skill.wall_thickness,
        caster.team,
    );

    print("  -> Built {d:.0}x{d:.0} wall at ({d:.1}, {d:.1})\n", .{
        skill.wall_length,
        skill.wall_height,
        ground_pos.x,
        ground_pos.z,
    });
}

/// Build a wall in front of the caster (for non-targeted wall skills)
pub fn buildWallInFront(
    terrain_grid: *TerrainGrid,
    skill: *const Skill,
    caster: *const Character,
    facing_angle: f32,
) void {
    if (!skill.creates_wall) return;

    terrain_grid.buildWallPerpendicular(
        caster.position.x,
        caster.position.z,
        facing_angle,
        skill.wall_distance_from_caster,
        skill.wall_length,
        skill.wall_height,
        skill.wall_thickness,
        caster.team,
    );

    print("{s} built {d:.0}x{d:.0} wall\n", .{
        caster.name,
        skill.wall_length,
        skill.wall_height,
    });
}

// ============================================================================
// WALL DESTRUCTION
// ============================================================================

/// Damage walls in an area (for wall-destroying skills)
pub fn damageWallsInArea(
    terrain_grid: *TerrainGrid,
    skill: *const Skill,
    center_x: f32,
    center_z: f32,
) void {
    if (!skill.destroys_walls or skill.aoe_radius <= 0) return;

    const wall_damage = skill.damage * skill.wall_damage_multiplier;
    terrain_grid.damageWallsInRadius(center_x, center_z, skill.aoe_radius, wall_damage);
    print("  -> Damaged walls for {d:.1}\n", .{wall_damage});
}

// ============================================================================
// FULL TERRAIN APPLICATION
// ============================================================================

/// Apply all terrain effects from a skill at a ground position
/// This handles terrain patches, walls, and wall destruction
pub fn applySkillTerrainEffects(
    terrain_grid: *TerrainGrid,
    skill: *const Skill,
    caster: *const Character,
    ground_pos: rl.Vector3,
) void {
    // Apply terrain effect (fire, ice, mud patches)
    applyTerrainShape(
        terrain_grid,
        skill.terrain_effect,
        ground_pos.x,
        ground_pos.z,
        skill.aoe_radius,
        caster.position,
    );

    // Build walls
    buildWallAtPosition(terrain_grid, skill, caster, ground_pos);

    // Damage walls in area
    damageWallsInArea(terrain_grid, skill, ground_pos.x, ground_pos.z);
}

// ============================================================================
// TESTS
// ============================================================================

test "terrain shape application" {
    // Would need TerrainGrid setup
    // Test that different shapes apply terrain correctly
}
