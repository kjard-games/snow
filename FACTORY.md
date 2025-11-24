# Snow Factory System

The Factory system provides a powerful, composable API for building characters, teams, and arena setups in Snow. Instead of manually creating hardcoded character arrays, you use builders to specify **constraints** and let the factory handle the complexity.

## Overview

The factory consists of three main builders:

- **CharacterBuilder**: Creates individual characters with specific schools, positions, equipment, and skills
- **TeamBuilder**: Assembles groups of characters with consistent positioning and constraints
- **ArenaBuilder**: Composes multiple teams (e.g., 3 teams for 3v3v3 or neutral NPCs)

## Basic Example: Random Character

```zig
var id_gen = entity.EntityIdGenerator{};
var rng = std.Random.DefaultPrng.init(seed).random();

var builder = factory.CharacterBuilder.init(allocator, &rng, &id_gen);
const char = builder
    .withTeam(.blue)
    .withColor(.blue)
    .build();
```

## Schools & Positions

Schools determine energy pools and active skills:
- `private_school`, `public_school`, `montessori`, `homeschool`, `waldorf`

Positions determine position skills:
- `pitcher`, `fielder`, `sledder`, `shoveler`, `animator`, `thermos` (healer)

### Force a Specific School & Position

```zig
const char = builder
    .withSchool(.waldorf)
    .withPosition(.thermos)
    .build();
```

## Equipment Constraints

Equipment can be specified exactly, by category, or by hand requirement:

```zig
const char1 = builder
    .withMainHand(.{ .specific = &equipment.BigShovel })
    .build();

const char2 = builder
    .withMainHand(.{ .category = .melee_weapon })
    .withOffHand(.{ .category = .shield })
    .build();

const char3 = builder
    .withMainHand(.{ .hand_requirement = .one_hand })
    .build();
```

## Skill Constraints

Force specific skills into specific slots (0-7):

```zig
// Guarantee a wall-building skill in slot 0
const char = builder
    .withWallSkillInSlot(0)
    .build();

// Place a specific skill in slot 4
const char = builder
    .withSkillInSlot(4, .{ .specific = &some_skill })
    .build();

// Fill slot 5 with any school skill
const char = builder
    .withSkillInSlot(5, .{ .any_from_school = .waldorf })
    .build();
```

Remaining slots are auto-filled with position/school skills.

## Building Teams

TeamBuilder handles positioning and composition:

```zig
var team = factory.TeamBuilder.init(allocator, &rng, &id_gen);

try team
    .withTeam(.blue)
    .withColor(.blue)
    .withBasePosition(.{ .x = 0, .y = 0, .z = 400 })
    .withSpacing(100.0) // Characters spaced 100 units apart
    .addCharacter(&char_builder_1)
    .addCharacter(&char_builder_2)
    .addCharacter(&char_builder_3)
    .addCharacter(&char_builder_4);

const characters = try team.build();
```

TeamBuilder automatically positions characters relative to the base position with consistent spacing.

### Composition Constraints

Add multiple characters matching a composition pattern:

```zig
var constraint = factory.CharacterCompositionConstraint{
    .school = .waldorf,
    .position = .thermos, // Must be thermos
    .min_count = 1,
    .max_count = 1, // Exactly 1 thermos healer
};

try team.addComposition(constraint, 1);
```

## Building Arena (3-Team Setup)

For 3v3v3 or mixed team configurations:

```zig
var arena = factory.ArenaBuilder.init(allocator, &rng, &id_gen);

// Add ally team
try {
    const allies = try arena.addTeam();
    allies.withTeam(.blue).withColor(.blue).withBasePosition(.{ .x = 0, .y = 0, .z = 400 });
    // ... add characters to allies
}

// Add enemy team  
try {
    const enemies = try arena.addTeam();
    enemies.withTeam(.red).withColor(.red).withBasePosition(.{ .x = 0, .y = 0, .z = -400 });
    // ... add characters to enemies
}

// Add neutral/3rd team
try {
    const neutrals = try arena.addTeam();
    neutrals.withTeam(.blue).withColor(.yellow).withBasePosition(.{ .x = -500, .y = 0, .z = 0 });
    // ... add characters to neutrals
}

// Collect all characters (returns owned slice)
const all_chars = try arena.buildAll(allocator);
defer allocator.free(all_chars);
```

## Telemetry Integration

The factory is fully compatible with telemetry:

```zig
var telem = try MatchTelemetry.init(allocator);
defer telem.deinit();

for (characters) |char| {
    try telem.registerEntity(
        char.id,
        char.name,
        @tagName(char.school),
        @tagName(char.player_position),
        if (char.team == .blue) 0 else 1, // Team ID
        false // Is player
    );
}
```

Factory-built characters report all their stats through standard telemetry channels.

## Real-World Examples

### "Have one Thermos on a team"

```zig
var thermos_char = factory.CharacterBuilder.init(allocator, &rng, &id_gen);
const healer = thermos_char
    .withPosition(.thermos)  // Forces healer position
    .build();

try team.addCharacter(&thermos_char);
```

### "Have one wall skill in the skill bar for one character"

```zig
var wall_char = factory.CharacterBuilder.init(allocator, &rng, &id_gen);
const defender = wall_char
    .withWallSkillInSlot(0)  // Guarantee wall skill in slot 0
    .build();
```

### "Build a balanced 4v4 with 1 healer per team"

```zig
var allies = factory.TeamBuilder.init(allocator, &rng, &id_gen);
allies.withTeam(.blue).withColor(.blue).withBasePosition(.{ .x = 0, .y = 0, .z = 400 });

// 3 damage dealers
for (0..3) |_| {
    var dmg = factory.CharacterBuilder.init(allocator, &rng, &id_gen);
    try allies.addCharacter(&dmg);
}

// 1 healer
var healer = factory.CharacterBuilder.init(allocator, &rng, &id_gen);
healer.withPosition(.thermos);
try allies.addCharacter(&healer);

const ally_team = try allies.build();
```

### "Different equipment for each school"

```zig
var waldorf_char = factory.CharacterBuilder.init(allocator, &rng, &id_gen);
const waldorf = waldorf_char
    .withSchool(.waldorf)
    .withMainHand(.{ .specific = &equipment.Slingshot }) // Waldorf uses slingshot
    .build();

var montessori_char = factory.CharacterBuilder.init(allocator, &rng, &id_gen);
const montessori = montessori_char
    .withSchool(.montessori)
    .withMainHand(.{ .specific = &equipment.BigShovel }) // Montessori uses shovel
    .build();
```

## Advanced: Custom Constraints

The constraint system is extensible. Add new constraint types by extending the unions:

```zig
// Current constraint types:
// - .none: No constraint
// - .specific: Exact equipment/skill
// - .category: Equipment category
// - .hand_requirement: Equipment hand type
// - .creates_wall: Wall-building skills
// - .destroys_wall: Wall-breaking skills
// - .any_from_school: Any skill from school
// - .any_from_position: Any skill from position
// - .in_slot: Must be in specific slot
```

To add a new constraint (e.g., "melee-focused"):

```zig
// In factory.zig:
pub const SkillConstraint = union(enum) {
    // ... existing variants ...
    melee_focused, // New!
};

// Then in resolveSkillConstraint():
.melee_focused => pickMeleeSkill(position_skills),
```

## File Structure

- `factory.zig`: Main factory implementation
  - `CharacterBuilder` struct
  - `TeamBuilder` struct
  - `ArenaBuilder` struct
  - Helper functions for constraint resolution

## Notes

- All builders use allocators for potential future features
- RNG is used for equipment/skill selection when not explicitly constrained
- Entity IDs are automatically generated (stable across ticks)
- Teams are positioned sequentially via `spacing` parameter
- Factory builds are composable - combine multiple team builders into an arena

## See Also

- `character.zig`: Character struct definition
- `equipment.zig`: Equipment definitions
- `skills.zig`: Skill definitions
- `position.zig`: Position-specific skill pools
- `telemetry.zig`: Match telemetry tracking
