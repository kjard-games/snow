# Agent Guidelines for Snow Codebase

## Build & Test Commands
- **Build**: `zig build`
- **Run**: `zig build run`
- **Test**: `zig build test` or `zig test <file>` for specific files
- **Balance testing**: Run `balance_test.zig` or `test_simulation_factory.zig`

## Project Overview

Snow is a GW1-inspired 3D tactical game built with Zig and Raylib. Key concepts:
- **Schools**: Private (White/Order), Public (Red/Aggression), Montessori (Green/Adaptation), Homeschool (Black/Sacrifice), Waldorf (Blue/Rhythm)
- **Positions**: Pitcher, Fielder, Sledder, Shoveler, Animator, Thermos (healer)
- **Resources**: Warmth (health), Energy, plus school-specific resources (Grit, Credit, Rhythm, Variety)
- **Conditions**: "Chills" (debuffs) and "Cozies" (buffs)
- **AP Skills**: "Advanced Placement" skills (like GW1 elites) - one per skill bar

## Architecture

### Core Systems
- **Entry point**: `main.zig` → `game_mode.zig` → `game_state.zig`
- **Fixed timestep**: 20Hz tick rate (`TICK_RATE_HZ = 20`, `TICK_RATE_SEC = 0.05`)
- **Entity IDs**: Stable references via `EntityId` (u32), `NULL_ENTITY = 0`
- **Multi-team**: Supports up to 4 teams (red, blue, yellow, green), max 12 entities

### Key Constants (game_state.zig)
```zig
MAX_ENTITIES: usize = 12
TICK_RATE_HZ: u32 = 20
TICK_RATE_MS: u32 = 50
TICK_RATE_SEC: f32 = 0.05
MAX_SKILLS: usize = 8  // Skill bar slots
```

### Module Organization
- `character.zig` re-exports from `character_*.zig` component modules
- `skills.zig` re-exports from `skills/types.zig`
- `school.zig` and `position.zig` delegate to skill modules in `skills/schools/` and `skills/positions/`
- `combat.zig` orchestrates via `combat_*.zig` modules

### Character Components
Main `Character` struct aggregates embedded component states:
- `CastingState` - skill bar, casting, cooldowns
- `ConditionState` - chills, cozies, active effects
- `SchoolResourceState` - grit, credit, rhythm, variety
- `CombatState` - auto-attack, damage monitor

## Key Patterns

### Builder Pattern (use for all game setup)
```zig
// Characters
var builder = factory.CharacterBuilder.init(allocator, &rng, &id_gen);
const char = builder.withTeam(.blue).withSchool(.waldorf).withPosition(.thermos).build();

// Teams
var team = factory.TeamBuilder.init(allocator, &rng, &id_gen);
try team.withTeam(.blue).addCharacter(&builder);

// Full simulations
var sim = try SimulationFactory.init(allocator);
try sim.withTeamSize(4).withFormat(.arena_4v4).build();
```

### Compositional Effects System (effects.zig)
Four dimensions for skill effects:
- **WHAT**: `EffectModifier` - what changes (damage, healing, conditions)
- **WHEN**: `EffectTiming` - when it triggers (on_activation, on_hit, over_time)
- **WHO**: `EffectTarget` - who is affected (self, target, nearby_allies)
- **IF**: `EffectCondition` - conditions for triggering

### Headless Testing
```zig
var builder = GameStateBuilder.init(allocator);
try builder.withRendering(false)  // Headless
           .withPlayerControl(false)  // AI-only
           .withSeed(12345);  // Deterministic RNG
```

## Code Style

### Imports & Structure
- Import order: std, external deps (raylib), then local modules
- Use explicit imports: `const rl = @import("raylib");`
- Type aliases at top after imports: `const Character = character.Character;`
- Section markers: `// ============================================`
- Subsection markers: `// ----------------------------------------------------------------------------`

### Naming Conventions
- Constants: `SCREAMING_SNAKE_CASE` (e.g., `MAX_SKILLS`, `TICK_RATE_HZ`)
- Types/Structs/Enums: `PascalCase` (e.g., `GameState`, `SkillType`)
- Functions/variables: `camelCase` (e.g., `updateEnergy`, `cast_time_remaining`)
- Private functions: prefix with underscore if needed, but prefer pub/private via scope

### Types & Safety
- Use explicit integer types: `u8`, `u32`, `f32`, etc.
- Compile-time safety checks with `comptime` blocks when validating constraints
- Prefer optionals (`?T`) over sentinel values for nullable references
- Use `@intCast`, `@floatFromInt`, `@intFromFloat` for explicit conversions
- Skills are defined as `comptime` constants in position/school modules

### Error Handling
- Propagate errors with `try` for recoverable errors
- Use `catch` with explicit error handling or fallback values
- Log errors: `std.log.err("message: {}", .{err});`
- Use `defer` for cleanup (e.g., `defer rl.closeWindow();`)

### Comments & Documentation
- Guild Wars 1 (GW1) mechanics are the design reference - note GW1-accurate behavior
- Explain WHY not WHAT: `// Energy cost is STILL incurred (no refund)`
- TODOs are common and acceptable: `// TODO: Natural warmth regeneration`
- Reference GW1 skill timing: activation time, aftercast, recharge

## Common Tasks

### Adding a New Skill
1. Define skill as `comptime const` in appropriate `skills/positions/` or `skills/schools/` file
2. Add to the position/school's skill list
3. Use `Effect` struct with appropriate modifiers, timing, target, conditions

### Creating Test Scenarios
1. Use `SimulationFactory` or `GameStateBuilder` - never manually construct GameState
2. Set `withRendering(false)` for headless tests
3. Use `withSeed(n)` for deterministic results
4. Check `test_simulation_factory.zig` for examples

### Modifying Character Behavior
- Stats: `character_stats.zig`
- Casting/skills: `character_casting.zig`
- Conditions: `character_conditions.zig`
- School resources: `character_school_resources.zig`
- Combat: `character_combat.zig`

## Don'ts
- Don't use array indices for entity targeting - use EntityId
- Don't manually construct GameState - use builders
- Don't hardcode character arrays - use factory system
- Don't mix frame-rate dependent and tick-based logic
