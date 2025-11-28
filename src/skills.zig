// ============================================================================
// SKILLS MODULE - Re-exports from skills/types.zig for backward compatibility
// ============================================================================
// The actual type definitions are in skills/types.zig
// School-specific skills are in skills/schools/*.zig
// Position-specific skills are in skills/positions/*.zig

const types = @import("skills/types.zig");

// Re-export all public types
pub const SkillTarget = types.SkillTarget;
pub const ProjectileType = types.ProjectileType;
pub const SkillMechanic = types.SkillMechanic;
pub const SkillType = types.SkillType;
pub const AoeType = types.AoeType;
pub const Chill = types.Chill;
pub const Cozy = types.Cozy;
pub const ChillEffect = types.ChillEffect;
pub const CozyEffect = types.CozyEffect;
pub const TerrainShape = types.TerrainShape;
pub const TerrainModifier = types.TerrainModifier;
pub const TerrainEffect = types.TerrainEffect;
pub const ActiveChill = types.ActiveChill;
pub const ActiveCozy = types.ActiveCozy;
pub const Skill = types.Skill;

// Skill behavior types
pub const SkillBehavior = types.SkillBehavior;
pub const SummonType = types.SummonType;
pub const SummonParams = types.SummonParams;
pub const LinkParams = types.LinkParams;
pub const RedirectParams = types.RedirectParams;
pub const ProjectileReturnParams = types.ProjectileReturnParams;
pub const PreventDeathParams = types.PreventDeathParams;
pub const Behavior = types.Behavior;
pub const BehaviorTrigger = types.BehaviorTrigger;
pub const BehaviorResponse = types.BehaviorResponse;
