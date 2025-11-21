const std = @import("std");
const entity = @import("entity.zig");
const skills = @import("skills.zig");

const Entity = entity.Entity;
const Skill = entity.Skill;
const print = std.debug.print;

pub const CastResult = enum {
    success,
    no_energy,
    out_of_range,
    no_target,
    target_dead,
    caster_dead,
};

pub fn castSkill(caster: *Entity, skill: *const Skill, target: ?*Entity) CastResult {
    // Check if caster is alive
    if (!caster.isAlive()) return .caster_dead;

    // Check energy
    if (caster.energy < skill.energy_cost) {
        print("{s} not enough energy ({d}/{d})\n", .{ caster.name, caster.energy, skill.energy_cost });
        return .no_energy;
    }

    // Check target
    const tgt = target orelse {
        print("{s} has no target\n", .{caster.name});
        return .no_target;
    };

    // Check if target is alive
    if (!tgt.isAlive()) return .target_dead;

    // Check range
    const distance = caster.distanceTo(tgt.*);
    if (distance > skill.cast_range) {
        print("{s} target out of range ({d:.1}/{d:.1})\n", .{ caster.name, distance, skill.cast_range });
        return .out_of_range;
    }

    // Consume energy
    caster.energy -= skill.energy_cost;

    // Apply damage
    const final_damage = skill.damage; // TODO: Add school-specific modifiers
    tgt.takeDamage(final_damage);

    print("{s} used {s} on {s} for {d:.1} damage! ({d:.1}/{d:.1} HP)\n", .{
        caster.name,
        skill.name,
        tgt.name,
        final_damage,
        tgt.health,
        tgt.max_health,
    });

    return .success;
}
