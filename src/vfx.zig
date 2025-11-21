const std = @import("std");
const rl = @import("raylib");
const entity_types = @import("entity.zig");

const EntityId = entity_types.EntityId;

// Maximum number of each effect type we can have active at once
pub const MAX_PROJECTILES: usize = 50;
pub const MAX_DAMAGE_NUMBERS: usize = 100;
pub const MAX_IMPACT_EFFECTS: usize = 50;
pub const MAX_HEAL_EFFECTS: usize = 30;

pub const EffectType = enum {
    damage,
    heal,
    miss,
};

// Projectile moving through 3D space
pub const Projectile = struct {
    active: bool = false,
    start_pos: rl.Vector3 = .{ .x = 0, .y = 0, .z = 0 },
    target_pos: rl.Vector3 = .{ .x = 0, .y = 0, .z = 0 },
    current_pos: rl.Vector3 = .{ .x = 0, .y = 0, .z = 0 },
    progress: f32 = 0.0, // 0.0 to 1.0
    speed: f32 = 500.0, // units per second
    color: rl.Color = .white,
    size: f32 = 5.0,
    caster_id: EntityId = 0,
    target_id: EntityId = 0,
    is_melee: bool = false, // Melee attacks are instant, just show a flash
};

// Floating damage/heal numbers
pub const DamageNumber = struct {
    active: bool = false,
    value: f32 = 0,
    position: rl.Vector3 = .{ .x = 0, .y = 0, .z = 0 },
    velocity: rl.Vector3 = .{ .x = 0, .y = 50.0, .z = 0 }, // Float upward
    lifetime: f32 = 1.5, // seconds
    time_remaining: f32 = 0,
    effect_type: EffectType = .damage,

    pub fn init(value: f32, position: rl.Vector3, effect_type: EffectType) DamageNumber {
        return DamageNumber{
            .active = true,
            .value = value,
            .position = position,
            .time_remaining = 1.5,
            .effect_type = effect_type,
        };
    }
};

// Impact effect (flash/burst at hit location)
pub const ImpactEffect = struct {
    active: bool = false,
    position: rl.Vector3 = .{ .x = 0, .y = 0, .z = 0 },
    lifetime: f32 = 0.3, // seconds
    time_remaining: f32 = 0,
    color: rl.Color = .red,
    size: f32 = 20.0,

    pub fn init(position: rl.Vector3, color: rl.Color) ImpactEffect {
        return ImpactEffect{
            .active = true,
            .position = position,
            .time_remaining = 0.3,
            .color = color,
        };
    }
};

// Heal effect (particles rising from character)
pub const HealEffect = struct {
    active: bool = false,
    position: rl.Vector3 = .{ .x = 0, .y = 0, .z = 0 },
    lifetime: f32 = 1.0, // seconds
    time_remaining: f32 = 0,
    size: f32 = 15.0,

    pub fn init(position: rl.Vector3) HealEffect {
        return HealEffect{
            .active = true,
            .position = position,
            .time_remaining = 1.0,
        };
    }
};

// Visual Effects Manager
pub const VFXManager = struct {
    projectiles: [MAX_PROJECTILES]Projectile = [_]Projectile{.{}} ** MAX_PROJECTILES,
    damage_numbers: [MAX_DAMAGE_NUMBERS]DamageNumber = [_]DamageNumber{.{}} ** MAX_DAMAGE_NUMBERS,
    impact_effects: [MAX_IMPACT_EFFECTS]ImpactEffect = [_]ImpactEffect{.{}} ** MAX_IMPACT_EFFECTS,
    heal_effects: [MAX_HEAL_EFFECTS]HealEffect = [_]HealEffect{.{}} ** MAX_HEAL_EFFECTS,

    pub fn init() VFXManager {
        return VFXManager{};
    }

    // Spawn a projectile from caster to target
    pub fn spawnProjectile(
        self: *VFXManager,
        start_pos: rl.Vector3,
        target_pos: rl.Vector3,
        caster_id: EntityId,
        target_id: EntityId,
        is_ranged: bool,
        color: rl.Color,
    ) void {
        // Find empty slot
        for (&self.projectiles) |*proj| {
            if (!proj.active) {
                proj.* = Projectile{
                    .active = true,
                    .start_pos = start_pos,
                    .target_pos = target_pos,
                    .current_pos = start_pos,
                    .color = color,
                    .caster_id = caster_id,
                    .target_id = target_id,
                    .is_melee = !is_ranged,
                    .speed = if (is_ranged) 500.0 else 9999.0, // Melee is "instant"
                };
                return;
            }
        }
        // If we get here, we're out of projectile slots (just drop it)
    }

    // Spawn a damage/heal number
    pub fn spawnDamageNumber(self: *VFXManager, value: f32, position: rl.Vector3, effect_type: EffectType) void {
        for (&self.damage_numbers) |*num| {
            if (!num.active) {
                num.* = DamageNumber.init(value, position, effect_type);
                return;
            }
        }
    }

    // Spawn an impact effect
    pub fn spawnImpact(self: *VFXManager, position: rl.Vector3, color: rl.Color) void {
        for (&self.impact_effects) |*impact| {
            if (!impact.active) {
                impact.* = ImpactEffect.init(position, color);
                return;
            }
        }
    }

    // Spawn a heal effect
    pub fn spawnHeal(self: *VFXManager, position: rl.Vector3) void {
        for (&self.heal_effects) |*heal| {
            if (!heal.active) {
                heal.* = HealEffect.init(position);
                return;
            }
        }
    }

    // Update all effects (called every tick)
    pub fn update(self: *VFXManager, dt: f32, entity_positions: []const EntityPosition) void {
        // Update projectiles
        for (&self.projectiles) |*proj| {
            if (!proj.active) continue;

            proj.progress += (proj.speed * dt) / vectorDistance(proj.start_pos, proj.target_pos);

            if (proj.progress >= 1.0) {
                // Projectile hit - spawn impact effect
                self.spawnImpact(proj.target_pos, proj.color);
                proj.active = false;
            } else {
                // Update position (lerp from start to target)
                proj.current_pos = vectorLerp(proj.start_pos, proj.target_pos, proj.progress);
            }
        }

        // Update damage numbers
        for (&self.damage_numbers) |*num| {
            if (!num.active) continue;

            num.time_remaining -= dt;
            if (num.time_remaining <= 0) {
                num.active = false;
            } else {
                // Move upward
                num.position.x += num.velocity.x * dt;
                num.position.y += num.velocity.y * dt;
                num.position.z += num.velocity.z * dt;
            }
        }

        // Update impact effects
        for (&self.impact_effects) |*impact| {
            if (!impact.active) continue;

            impact.time_remaining -= dt;
            if (impact.time_remaining <= 0) {
                impact.active = false;
            }
        }

        // Update heal effects
        for (&self.heal_effects) |*heal| {
            if (!heal.active) continue;

            heal.time_remaining -= dt;
            if (heal.time_remaining <= 0) {
                heal.active = false;
            }
        }

        _ = entity_positions; // For future: update positions to track moving entities
    }

    // Draw all 3D effects
    pub fn draw3D(self: *const VFXManager) void {
        // Draw projectiles
        for (self.projectiles) |proj| {
            if (!proj.active) continue;

            if (proj.is_melee) {
                // Melee "projectiles" are just a quick line flash
                if (proj.progress < 0.2) { // Only show for first 20% of "travel"
                    rl.drawLine3D(proj.start_pos, proj.target_pos, proj.color);
                }
            } else {
                // Ranged projectiles are spheres
                rl.drawSphere(proj.current_pos, proj.size, proj.color);
            }
        }

        // Draw impact effects (expanding spheres that fade)
        for (self.impact_effects) |impact| {
            if (!impact.active) continue;

            const alpha_factor = impact.time_remaining / impact.lifetime;
            const current_size = impact.size * (1.0 + (1.0 - alpha_factor) * 2.0); // Expand over time

            // Fade alpha based on lifetime
            var color = impact.color;
            color.a = @as(u8, @intFromFloat(255.0 * alpha_factor));

            rl.drawSphere(impact.position, current_size, color);
        }

        // Draw heal effects (rising green particles)
        for (self.heal_effects) |heal| {
            if (!heal.active) continue;

            const alpha_factor = heal.time_remaining / heal.lifetime;
            const rise_offset = (1.0 - alpha_factor) * 50.0; // Rise up over lifetime

            var pos = heal.position;
            pos.y += rise_offset;

            var color = rl.Color.lime;
            color.a = @as(u8, @intFromFloat(255.0 * alpha_factor));

            rl.drawSphere(pos, heal.size, color);
        }
    }

    // Draw all 2D effects (damage numbers)
    pub fn draw2D(self: *const VFXManager, camera: rl.Camera) void {
        for (self.damage_numbers) |num| {
            if (!num.active) continue;

            // Convert 3D position to screen space
            const screen_pos = rl.getWorldToScreen(num.position, camera);

            // Skip if off-screen
            const screen_width = rl.getScreenWidth();
            const screen_height = rl.getScreenHeight();
            if (screen_pos.x < 0 or screen_pos.x > @as(f32, @floatFromInt(screen_width)) or
                screen_pos.y < 0 or screen_pos.y > @as(f32, @floatFromInt(screen_height)))
            {
                continue;
            }

            // Calculate alpha fade
            const alpha_factor = num.time_remaining / num.lifetime;

            // Choose color and format based on effect type
            var color: rl.Color = undefined;
            var text_buffer: [32]u8 = undefined;
            const text = switch (num.effect_type) {
                .damage => blk: {
                    color = rl.Color.red;
                    break :blk std.fmt.bufPrintZ(&text_buffer, "-{d:.0}", .{num.value}) catch "DMG";
                },
                .heal => blk: {
                    color = rl.Color.lime;
                    break :blk std.fmt.bufPrintZ(&text_buffer, "+{d:.0}", .{num.value}) catch "HEAL";
                },
                .miss => blk: {
                    color = rl.Color.gray;
                    break :blk "MISS";
                },
            };

            color.a = @as(u8, @intFromFloat(255.0 * alpha_factor));

            const font_size: i32 = 20;
            const text_width = rl.measureText(text, font_size);
            const x: i32 = @as(i32, @intFromFloat(screen_pos.x)) - @divTrunc(text_width, 2);
            const y: i32 = @as(i32, @intFromFloat(screen_pos.y));

            // Draw with outline for readability
            rl.drawText(text, x - 1, y - 1, font_size, .black);
            rl.drawText(text, x + 1, y - 1, font_size, .black);
            rl.drawText(text, x - 1, y + 1, font_size, .black);
            rl.drawText(text, x + 1, y + 1, font_size, .black);
            rl.drawText(text, x, y, font_size, color);
        }
    }
};

// Helper for tracking entity positions (for projectile target tracking)
pub const EntityPosition = struct {
    id: EntityId,
    position: rl.Vector3,
};

// Helper functions
fn vectorDistance(a: rl.Vector3, b: rl.Vector3) f32 {
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const dz = b.z - a.z;
    return @sqrt(dx * dx + dy * dy + dz * dz);
}

fn vectorLerp(a: rl.Vector3, b: rl.Vector3, t: f32) rl.Vector3 {
    return rl.Vector3{
        .x = a.x + (b.x - a.x) * t,
        .y = a.y + (b.y - a.y) * t,
        .z = a.z + (b.z - a.z) * t,
    };
}
