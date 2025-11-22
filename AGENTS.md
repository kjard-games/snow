# Agent Guidelines for Snow Codebase

## Build & Test Commands
- **Build**: `zig build`
- **Run**: `zig build run`
- **Test**: `zig test <file>` (no integrated test command in build.zig)

## Code Style

### Imports & Structure
- Import order: std, external deps (raylib), then local modules
- Use explicit imports: `const rl = @import("raylib");`
- Type aliases at top after imports: `const Character = character.Character;`

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

### Error Handling
- Propagate errors with `try` for recoverable errors
- Use `catch` with explicit error handling or fallback values
- Log errors: `std.log.err("message: {}", .{err});`
- Use `defer` for cleanup (e.g., `defer rl.closeWindow();`)

### Comments & Documentation
- Guild Wars 1 (GW1) mechanics are the design reference - note GW1-accurate behavior
- Explain WHY not WHAT: `// Energy cost is STILL incurred (no refund)`
- TODOs are common and acceptable: `// TODO: Natural warmth regeneration`
