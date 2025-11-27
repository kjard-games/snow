const types = @import("../types.zig");
const Skill = types.Skill;

// ============================================================================
// HOMESCHOOL SKILLS - Black: Sacrifice, Power, Isolation
// ============================================================================
// Theme: Pay health for power, devastating single-target, isolation bonuses
// Synergizes with: High damage, life sacrifice, solo play
// Cooldowns: 20-40s (long but devastating)

const homeschool_brain_freeze = [_]types.ChillEffect{.{
    .chill = .brain_freeze,
    .duration_ms = 10000,
    .stack_intensity = 1,
}};

const homeschool_packed = [_]types.ChillEffect{.{
    .chill = .packed_snow,
    .duration_ms = 12000,
    .stack_intensity = 1,
}};

const homeschool_fire = [_]types.CozyEffect{.{
    .cozy = .fire_inside,
    .duration_ms = 10000,
    .stack_intensity = 1,
}};

const homeschool_windburn = [_]types.ChillEffect{.{
    .chill = .windburn,
    .duration_ms = 8000,
    .stack_intensity = 1,
}};

const homeschool_numb = [_]types.ChillEffect{.{
    .chill = .numb,
    .duration_ms = 8000,
    .stack_intensity = 1,
}};

pub const skills = [_]Skill{
    // 1. Warmth for damage
    .{
        .name = "Blood Pact",
        .description = "Trick. Sacrifice 15% of your max Warmth. Deals 35 damage.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 5,
        .warmth_cost_percent = 0.15,
        .min_warmth_percent = 0.20, // Can't cast below 20% warmth
        .damage = 35.0,
        .cast_range = 220.0,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 25000,
    },

    // 2. Convert warmth to energy
    .{
        .name = "Isolated Study",
        .description = "Gesture. Sacrifice 20% of your max Warmth. Gain 15 energy.",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 0,
        .warmth_cost_percent = 0.20,
        .min_warmth_percent = 0.25, // Can't cast below 25% warmth
        .target_type = .self,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 30000,
        .grants_energy_on_hit = 15, // Grants on cast complete
    },

    // 3. Crippling curse
    .{
        .name = "Malnutrition",
        .description = "Trick. Sacrifice 10% of your max Warmth. Deals 12 damage. Inflicts Packed Snow (12 seconds).",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 8,
        .warmth_cost_percent = 0.10,
        .min_warmth_percent = 0.15,
        .damage = 12.0,
        .cast_range = 200.0,
        .activation_time_ms = 2000,
        .aftercast_ms = 750,
        .recharge_time_ms = 30000,
        .chills = &homeschool_packed,
    },

    // 4. Execute - kills low warmth targets (no sacrifice - pure energy)
    .{
        .name = "Final Exam",
        .description = "Throw. Deals 25 damage. Deals double damage if target foe is below 30% Warmth. Completely soaks through padding.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 12,
        .damage = 25.0,
        .bonus_damage_if_foe_below_50_warmth = 25.0, // Double damage vs low warmth
        .cast_range = 220.0,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 35000,
        .soak = 1.0,
    },

    // 5. Energy drain with sacrifice
    .{
        .name = "Social Anxiety",
        .description = "Trick. Sacrifice 8% of your max Warmth. Deals 10 damage. Inflicts Brain Freeze and steals 8 energy.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 6,
        .warmth_cost_percent = 0.08,
        .min_warmth_percent = 0.10,
        .damage = 10.0,
        .cast_range = 200.0,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 20000,
        .chills = &homeschool_brain_freeze,
        .grants_energy_on_hit = 8, // Steals energy
    },

    // 6. Power at a cost - constant warmth drain
    .{
        .name = "Obsession",
        .description = "Stance. Sacrifice 12% of your max Warmth. (12 seconds.) You deal +50% damage. You lose 1 Warmth per second.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 8,
        .warmth_cost_percent = 0.12,
        .min_warmth_percent = 0.15,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 40000,
        .duration_ms = 12000,
        .cozies = &homeschool_fire,
        // TODO: -1 warmth per second while active
    },

    // 7. Life steal - no sacrifice, sustain skill
    .{
        .name = "Vampiric Touch",
        .description = "Throw. Deals 20 damage. You gain 20 Warmth.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 8,
        .damage = 20.0,
        .healing = 20.0,
        .cast_range = 180.0,
        .target_type = .self,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 25000,
    },

    // 8. Devastating AoE with massive warmth cost
    .{
        .name = "Meltdown",
        .description = "Elite Trick. Sacrifice 25% of your max Warmth. Deals 35 damage to target and nearby foes.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 12,
        .warmth_cost_percent = 0.25,
        .min_warmth_percent = 0.30,
        .damage = 35.0,
        .cast_range = 240.0,
        .activation_time_ms = 3000,
        .aftercast_ms = 750,
        .recharge_time_ms = 40000,
        .aoe_type = .area,
        .aoe_radius = 180.0,
    },

    // 9. WALL: Blood Wall - powerful wall at health cost
    .{
        .name = "Blood Wall",
        .description = "Trick. Sacrifice 18% of your max Warmth. Build a tall, jagged wall of frozen blood.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 8,
        .warmth_cost_percent = 0.18,
        .min_warmth_percent = 0.22,
        .target_type = .ground,
        .cast_range = 150.0,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 35000,
        .creates_wall = true,
        .wall_length = 70.0,
        .wall_height = 45.0, // Very tall wall - paid in blood
        .wall_thickness = 22.0,
        .wall_distance_from_caster = 45.0,
        // TODO: Wall damages enemies who touch it (life steal theme)
    },

    // 10. Dark Knowledge - sacrifice for energy and damage buff
    .{
        .name = "Dark Knowledge",
        .description = "Gesture. Sacrifice 15% Warmth. Gain 10 energy. Your next attack deals +50% damage.",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 0,
        .warmth_cost_percent = 0.15,
        .min_warmth_percent = 0.20,
        .target_type = .self,
        .activation_time_ms = 500,
        .aftercast_ms = 500,
        .recharge_time_ms = 20000,
        .grants_energy_on_hit = 10,
        .cozies = &homeschool_fire,
    },

    // 11. Forbidden Technique - high damage with heavy sacrifice
    .{
        .name = "Forbidden Technique",
        .description = "Throw. Sacrifice 20% Warmth. Deals 45 damage. Unblockable.",
        .skill_type = .throw,
        .mechanic = .windup,
        .energy_cost = 10,
        .warmth_cost_percent = 0.20,
        .min_warmth_percent = 0.25,
        .damage = 45.0,
        .cast_range = 200.0,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 25000,
        .unblockable = true,
    },

    // 12. Solitary Strength - bonus when alone
    .{
        .name = "Solitary Strength",
        .description = "Stance. (20 seconds.) While no allies are nearby, deal +40% damage and take 20% less.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 5,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 30000,
        .duration_ms = 20000,
    },

    // 13. Bitter Cold - powerful DoT
    .{
        .name = "Bitter Lesson",
        .description = "Trick. Sacrifice 8% Warmth. Deals 10 damage. Inflicts Windburn (8 seconds).",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 6,
        .warmth_cost_percent = 0.08,
        .min_warmth_percent = 0.12,
        .damage = 10.0,
        .cast_range = 200.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 15000,
        .chills = &homeschool_windburn,
    },

    // 14. Self-Reliance - powerful self-heal at a cost
    .{
        .name = "Self-Reliance",
        .description = "Gesture. Sacrifice 10% max Warmth permanently. Heal to full Warmth.",
        .skill_type = .gesture,
        .mechanic = .ready,
        .energy_cost = 0,
        .healing = 200.0,
        .target_type = .self,
        .activation_time_ms = 2000,
        .aftercast_ms = 750,
        .recharge_time_ms = 60000,
        // TODO: Reduce max warmth by 10% permanently
    },

    // 15. Crushing Isolation - debuff spread
    .{
        .name = "Crushing Isolation",
        .description = "Trick. Sacrifice 5% Warmth. Deals 12 damage. Inflicts Numb (8 seconds). +50% duration if target has no allies nearby.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 8,
        .warmth_cost_percent = 0.05,
        .min_warmth_percent = 0.08,
        .damage = 12.0,
        .cast_range = 180.0,
        .activation_time_ms = 1000,
        .aftercast_ms = 750,
        .recharge_time_ms = 18000,
        .chills = &homeschool_numb,
    },

    // 16. Martyrdom - damage self to buff allies
    .{
        .name = "Martyrdom",
        .description = "Call. Sacrifice 25% Warmth. All allies gain +25% damage and heal 20 Warmth.",
        .skill_type = .call,
        .mechanic = .shout,
        .energy_cost = 10,
        .warmth_cost_percent = 0.25,
        .min_warmth_percent = 0.30,
        .healing = 20.0,
        .target_type = .ally,
        .aoe_type = .area,
        .aoe_radius = 250.0,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 35000,
        .duration_ms = 12000,
    },

    // ========================================================================
    // HOMESCHOOL AP SKILLS (4 AP skills for 20% of 20 total)
    // ========================================================================

    // AP 1: Blood Magic - convert warmth directly to damage
    .{
        .name = "Blood Magic",
        .description = "[AP] Stance. (30 seconds.) Your skills cost no energy but cost 5% max Warmth instead. Deal +30% damage.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 0,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 60000,
        .duration_ms = 30000,
        .is_ap = true,
    },

    // AP 2: Soul Bargain - trade warmth for power
    .{
        .name = "Soul Bargain",
        .description = "[AP] Trick. Sacrifice 50% of your current Warmth. Deal that amount as damage to target. Cannot kill yourself.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 5,
        .cast_range = 200.0,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 30000,
        .is_ap = true,
    },

    // AP 3: Infectious Isolation - spread debuffs
    .{
        .name = "Infectious Isolation",
        .description = "[AP] Trick. For 15 seconds, whenever target takes damage, the Chills on them spread to the nearest foe.",
        .skill_type = .trick,
        .mechanic = .concentrate,
        .energy_cost = 12,
        .cast_range = 200.0,
        .activation_time_ms = 1500,
        .aftercast_ms = 750,
        .recharge_time_ms = 40000,
        .duration_ms = 15000,
        .is_ap = true,
    },

    // AP 4: Lone Wolf - massive solo power
    .{
        .name = "Lone Wolf",
        .description = "[AP] Stance. While no allies are within 300 units: +60% damage, +40% armor, +50% energy regen. Lose all bonuses if ally comes near.",
        .skill_type = .stance,
        .mechanic = .shift,
        .energy_cost = 10,
        .target_type = .self,
        .activation_time_ms = 0,
        .aftercast_ms = 0,
        .recharge_time_ms = 45000,
        .duration_ms = 60000,
        .is_ap = true,
    },
};
