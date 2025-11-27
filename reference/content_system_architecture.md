# Content System Architecture

A content-addressable game definition system where the entire "rules of the game" can be versioned, distributed, and experimented with.

## Design Goals

- **Minecraft-style multiplayer**: Server<>client relationship, solo players run their own server, seamless host migration by drip-feeding state to other players' servers
- **Skill experimentation**: Write and test skills easily, store in SQLite
- **Live updates**: Update content and have players play on "versions" of skill-packs
- **Standard format**: Maintain consistency across all content types

---

## The Complete Content Model

```
GameDefinition (the complete "ruleset")
|
+-- SkillPacks[]        - What you can DO
+-- GearPacks[]         - What you can WEAR
+-- SchoolPacks[]       - WHO you can BE (class/resource systems)
+-- PositionPacks[]     - WHERE you play (roles/archetypes)
+-- TerrainPacks[]      - WHAT the world is made of
+-- EffectPacks[]       - HOW things interact (the grammar)
+-- MatchRules          - Victory conditions, team sizes, etc.
```

---

## Content Layer Summary

| Layer | What It Does | Current File |
|-------|-------------|--------------|
| **Skills** | What you DO (abilities) | `skills.zig`, `school.zig`, `position.zig` |
| **Gear** | What you WEAR/HOLD (stats) | `equipment.zig`, `gear_slot.zig` |
| **Schools** | WHO you ARE (class identity) | `school.zig` |
| **Positions** | Your ROLE (archetype) | `position.zig` |
| **Effects** | HOW things interact (grammar) | `effects.zig` |
| **Terrain** | The WORLD (environment) | `terrain.zig` |
| **Match Rules** | The RULES (win conditions) | *Not yet implemented* |

---

## Effects: The Grammar of the Game

Effects are **not user-facing content** - players don't pick "effects". Effects are the **building blocks** that skills compose together. They're the grammar/primitives that define HOW things interact.

### The Four Dimensions of an Effect

Every effect answers four questions:

| Dimension | Question | Current Enum | Examples |
|-----------|----------|--------------|----------|
| **WHAT** | What changes? | `EffectModifier` | damage_multiplier, move_speed_multiplier, block_chance |
| **WHEN** | When does it trigger? | `EffectTiming` | on_hit, on_cast, while_active, on_block |
| **WHO** | Who is affected? | `EffectTarget` | self, target, adjacent_to_target, allies_in_earshot |
| **IF** | What condition gates it? | `EffectCondition` | always, if_target_below_50_percent_warmth, if_caster_has_grit_5_plus |

### Schema vs Instances

The current `effects.zig` has two distinct parts:

1. **Schema** (the enums/structs) - These define WHAT effects CAN do
   - `EffectModifier` - 20+ modifier types (damage, speed, armor, blocking, etc.)
   - `EffectTiming` - 14 trigger moments (on_hit, on_cast, on_block, etc.)
   - `EffectTarget` - 11 targeting modes (self, target, AoE, etc.)
   - `EffectCondition` - 60+ conditions (warmth, status, terrain, school resources)

2. **Instances** (the const values) - These are actual effects skills reference
   - `SOAKED_THROUGH_EFFECT` - Take 2x damage for 5s
   - `MOMENTUM_EFFECT` - 50% speed + 20% CDR for 6s
   - `COZY_LAYERS_EFFECT` - Flash enchantment with on_removed_early chain

### Effects in the Content Model

**Key Insight:** Effects are the **engine layer**, not the content layer. The schema (enums) are part of the game engine. The instances are content that can be serialized.

```
┌─────────────────────────────────────────────────────────────┐
│                      ENGINE (Compiled)                       │
│  EffectModifier, EffectTiming, EffectTarget, EffectCondition│
│  Effect struct, evaluateCondition(), calculateDamageMultiplier() │
└─────────────────────────────────────────────────────────────┘
                              ↑
                              │ references
┌─────────────────────────────────────────────────────────────┐
│                   CONTENT (Data-driven)                      │
│  SOAKED_THROUGH_EFFECT, MOMENTUM_EFFECT, etc.               │
│  Stored in SQLite, serialized as JSON, loaded at runtime    │
└─────────────────────────────────────────────────────────────┘
                              ↑
                              │ references
┌─────────────────────────────────────────────────────────────┐
│                      SKILLS (Data-driven)                    │
│  Quick Toss, Frost Barrage, Rally Cry, etc.                 │
│  Each skill has effects: []const *const Effect              │
└─────────────────────────────────────────────────────────────┘
```

### Effect Serialization (JSON)

```json
{
  "effect_id": "soaked_through",
  "name": "Soaked Through",
  "description": "Wet clothes make you vulnerable - take 2x damage",
  "modifiers": [
    { "type": "damage_multiplier", "value": 2.0 }
  ],
  "timing": "on_hit",
  "target": "target",
  "condition": "always",
  "duration_ms": 5000,
  "is_buff": false,
  "max_stacks": 1,
  "stack_behavior": "refresh_duration",
  "chain_effects": {
    "on_end": null,
    "on_removed_early": null,
    "initial": null
  }
}
```

### Effect Chains (Dervish-style Flash Enchantments)

Effects can trigger other effects:

```
COZY_LAYERS_EFFECT (buff: 25% damage reduction, 25% slow)
    │
    └── on_removed_early → COZY_LAYERS_SHED_EFFECT (debuff: slow adjacent foes)

QUICK_REFLEXES_EFFECT (block next attack)
    │
    └── on_end (after block) → QUICK_REFLEXES_FOLLOWUP_EFFECT (33% speed boost)
```

### Why Effects Are Engine, Not Content

**The enum values are hardcoded** because:
1. The combat system needs to know what `damage_multiplier` means
2. The condition evaluation needs to know how to check `if_target_below_50_percent_warmth`
3. Adding new modifier types requires code changes to apply them

**The effect instances are content** because:
1. They're just combinations of existing primitives
2. Balancing them doesn't require code changes
3. Modders can create new effects by composing existing modifiers

### Expanding the Effect System

To add a new **modifier type** (engine change):
1. Add to `EffectModifier` enum
2. Add to `calculateXxxMultiplier()` helper functions
3. Update combat system to apply it

To add a new **effect instance** (content change):
1. Define modifiers array with existing modifier types
2. Create Effect struct with timing/target/condition
3. Register in effect pack

To add a new **condition** (engine change):
1. Add to `EffectCondition` enum
2. Add case to `evaluateConditionFull()`
3. Add field to `ConditionContext` if new state needed

### Effect Categories by Purpose

| Category | Examples | Use Case |
|----------|----------|----------|
| **Damage Modifiers** | SOAKED_THROUGH, FINISHING_BLOW | Spike damage, vulnerability |
| **Speed Modifiers** | MOMENTUM, ICE_MASTERY | Chase/kite, terrain advantage |
| **Defensive** | SNOWBALL_SHIELD, COZY_LAYERS | Blocking, damage reduction |
| **Resource** | FIRED_UP, WIND_KNOCKED | Energy manipulation |
| **Disables** | BRAIN_FREEZE, NUMB_FINGERS | Interrupts, silences |
| **Chains** | QUICK_REFLEXES, COZY_LAYERS | Dervish-style flash enchantments |
| **Conditionals** | DESPERATE_MEASURES, GRIT_SURGE | School-specific synergies |
| **AoE** | RALLY_CRY, INTIMIDATING_PRESENCE | Party buffs, enemy debuffs |
| **Reactive** | THORNS, COUNTER_STANCE | Triggered on damage/block |

---

## Database Schema

```sql
-- Core versioning tables
CREATE TABLE game_versions (
    id INTEGER PRIMARY KEY,
    version_string TEXT NOT NULL,      -- "1.2.0"
    content_hash TEXT NOT NULL,        -- SHA256 of all pack hashes
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    author TEXT,
    is_official BOOLEAN DEFAULT FALSE,
    parent_version_id INTEGER REFERENCES game_versions(id)
);

CREATE TABLE content_packs (
    id INTEGER PRIMARY KEY,
    game_version_id INTEGER REFERENCES game_versions(id),
    pack_type TEXT NOT NULL,           -- 'skill', 'gear', 'school', 'effect', 'position', 'terrain'
    name TEXT NOT NULL,
    version TEXT NOT NULL,
    content_hash TEXT NOT NULL,        -- SHA256 of pack contents
    schema_version INTEGER NOT NULL,
    author TEXT,
    data BLOB,                         -- Serialized content (JSON or MessagePack)
    signature TEXT,                    -- Optional cryptographic signature
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE(name, version)
);

-- Individual content tables (denormalized for query performance)
CREATE TABLE skills (
    id INTEGER PRIMARY KEY,
    pack_id INTEGER REFERENCES content_packs(id),
    skill_id TEXT NOT NULL,            -- Unique within pack ("quick_toss")
    name TEXT NOT NULL,
    skill_type TEXT NOT NULL,          -- 'throw', 'trick', 'stance', 'call', 'gesture'
    mechanic TEXT NOT NULL,            -- 'windup', 'concentrate', 'shout', 'shift', 'ready', 'reflex'
    energy_cost INTEGER,
    timing_data TEXT,                  -- JSON: {activation_ms, aftercast_ms, recharge_ms}
    damage_data TEXT,                  -- JSON: {base, conditional_bonuses}
    targeting_data TEXT,               -- JSON: {type, range, aoe_type, aoe_radius}
    effects_refs TEXT,                 -- JSON array of effect IDs
    school_costs TEXT,                 -- JSON: {grit_cost, warmth_cost_percent, etc}
    is_ap BOOLEAN DEFAULT FALSE,
    full_data TEXT,                    -- Complete JSON for runtime loading
    
    UNIQUE(pack_id, skill_id)
);

CREATE TABLE gear (
    id INTEGER PRIMARY KEY,
    pack_id INTEGER REFERENCES content_packs(id),
    gear_id TEXT NOT NULL,
    name TEXT NOT NULL,
    gear_type TEXT NOT NULL,           -- 'equipment' (held) or 'clothing' (worn)
    slot TEXT,                         -- For clothing: 'toque', 'scarf', etc.
    hand_requirement TEXT,             -- For equipment: 'two_hands', 'one_hand', 'worn'
    category TEXT,                     -- 'throwing_tool', 'melee_weapon', 'shield', etc.
    stats TEXT,                        -- JSON: {damage, armor, speed_modifier, etc}
    effects_refs TEXT,                 -- JSON array of effect IDs
    full_data TEXT,
    
    UNIQUE(pack_id, gear_id)
);

CREATE TABLE schools (
    id INTEGER PRIMARY KEY,
    pack_id INTEGER REFERENCES content_packs(id),
    school_id TEXT NOT NULL,
    name TEXT NOT NULL,
    color_identity TEXT,               -- 'White', 'Red', 'Green', 'Black', 'Blue'
    resource_name TEXT,
    base_energy INTEGER,
    energy_regen REAL,
    mechanic_data TEXT,                -- JSON: school-specific mechanics
    skill_refs TEXT,                   -- JSON array of skill IDs belonging to this school
    full_data TEXT,
    
    UNIQUE(pack_id, school_id)
);

CREATE TABLE effects (
    id INTEGER PRIMARY KEY,
    pack_id INTEGER REFERENCES content_packs(id),
    effect_id TEXT NOT NULL,           -- Unique within pack ("soaked_through")
    name TEXT NOT NULL,
    description TEXT,
    timing TEXT NOT NULL,              -- 'on_hit', 'on_cast', 'while_active', etc.
    target TEXT NOT NULL,              -- 'self', 'target', 'adjacent_to_target', etc.
    condition TEXT DEFAULT 'always',   -- 'always', 'if_target_below_50_percent_warmth', etc.
    modifiers TEXT NOT NULL,           -- JSON array of {type, value}
    duration_ms INTEGER NOT NULL,
    is_buff BOOLEAN NOT NULL,
    max_stacks INTEGER DEFAULT 0,
    stack_behavior TEXT DEFAULT 'refresh_duration',
    priority INTEGER DEFAULT 0,
    -- Effect chains (Dervish-style flash enchantments)
    on_end_effect_id TEXT,             -- effect_id to trigger when duration expires
    on_removed_early_effect_id TEXT,   -- effect_id to trigger when stripped
    initial_effect_id TEXT,            -- effect_id to trigger on cast
    full_data TEXT,
    
    UNIQUE(pack_id, effect_id),
    FOREIGN KEY(on_end_effect_id) REFERENCES effects(effect_id),
    FOREIGN KEY(on_removed_early_effect_id) REFERENCES effects(effect_id),
    FOREIGN KEY(initial_effect_id) REFERENCES effects(effect_id)
);

-- Junction table for skills -> effects (many-to-many)
CREATE TABLE skill_effects (
    id INTEGER PRIMARY KEY,
    skill_id INTEGER REFERENCES skills(id),
    effect_id INTEGER REFERENCES effects(id),
    apply_order INTEGER DEFAULT 0,     -- Order effects are applied
    UNIQUE(skill_id, effect_id)
);

CREATE TABLE positions (
    id INTEGER PRIMARY KEY,
    pack_id INTEGER REFERENCES content_packs(id),
    position_id TEXT NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    stat_bonuses TEXT,                 -- JSON: {warmth_bonus, energy_bonus, speed_modifier}
    skill_affinities TEXT,             -- JSON array of preferred skill types
    gear_affinities TEXT,              -- JSON array of preferred gear categories
    school_affinities TEXT,            -- JSON array of synergistic schools
    playstyle_tags TEXT,               -- JSON array: ['frontline', 'support', 'burst', etc]
    passive_effects TEXT,              -- JSON array of effect IDs
    full_data TEXT,
    
    UNIQUE(pack_id, position_id)
);

-- Player/server preferences
CREATE TABLE pack_subscriptions (
    id INTEGER PRIMARY KEY,
    pack_name TEXT NOT NULL,
    pinned_version TEXT,               -- NULL = use latest
    auto_update BOOLEAN DEFAULT TRUE,
    subscribed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Index for fast lookups
CREATE INDEX idx_skills_pack ON skills(pack_id);
CREATE INDEX idx_gear_pack ON gear(pack_id);
CREATE INDEX idx_effects_pack ON effects(pack_id);
CREATE INDEX idx_packs_hash ON content_packs(content_hash);
```

---

## Position System (Implemented: `position.zig`)

Positions are roles/archetypes that define playstyle. Each position has:
- A unique skill pool (10-12 skills per position)
- Primary school synergies
- Range preferences (min/max effective range)

```zig
// Current implementation in position.zig
pub const Position = enum {
    pitcher,   // Pure Damage Dealer - the kid with the cannon arm
    fielder,   // Balanced Generalist - athletic all-rounder
    sledder,   // Aggressive Skirmisher - sled charge attacks
    shoveler,  // Tank/Defender - digs in, builds walls
    animator,  // Summoner/Necromancer - brings snowmen to life (Calvin & Hobbes style)
    thermos,   // Healer/Support - brings hot cocoa and hand warmers

    pub fn getSkills(self: Position) []const Skill { ... }
    pub fn getDescription(self: Position) [:0]const u8 { ... }
    pub fn getPrimarySchools(self: Position) []const School { ... }
    pub fn getRangeMin(self: Position) f32 { ... }
    pub fn getRangeMax(self: Position) f32 { ... }
};
```

### Current Positions

| Position | Role | Range | Primary Schools |
|----------|------|-------|-----------------|
| **Pitcher** | Pure Damage Dealer | 200-300 | Public School, Homeschool |
| **Fielder** | Balanced Generalist | 150-220 | Montessori, Public School |
| **Sledder** | Aggressive Skirmisher | 80-150 | Public School, Waldorf |
| **Shoveler** | Tank/Defender | 100-160 | Private School, Homeschool |
| **Animator** | Summoner/Necromancer | 180-240 | Homeschool, Waldorf |
| **Thermos** | Healer/Support | 150-200 | Waldorf, Private School |

### Future Enhancements for Content System

When moving to data-driven positions, consider adding:
```zig
// Extended Position data for content packs
pub const PositionData = struct {
    // Current fields
    name: [:0]const u8,
    description: [:0]const u8,
    primary_schools: []const School,
    range_min: f32,
    range_max: f32,
    
    // New fields for content system
    warmth_bonus: f32 = 0.0,
    energy_bonus: u8 = 0,
    speed_modifier: f32 = 1.0,
    preferred_skill_types: []const SkillType,
    preferred_gear_categories: []const EquipmentCategory,
    passive_effects: []const *const Effect,
    playstyle_tags: []const PlaystyleTag,
};

pub const PlaystyleTag = enum {
    frontline,      // Gets in close
    backline,       // Stays at range
    support,        // Heals/buffs allies
    disruptor,      // Interrupts/debuffs
    burst,          // High damage spikes
    sustained,      // Consistent pressure
    mobile,         // High movement
    anchor,         // Holds position
};
```

---

## Serialization Format (JSON)

```json
{
  "schema_version": 1,
  "pack_type": "skill",
  "pack_id": "core_skills",
  "version": "1.0.0",
  "content_hash": "sha256:abc123...",
  "author": "snow_dev",
  "created_at": "2024-01-15T10:30:00Z",
  
  "skills": [
    {
      "id": "quick_toss",
      "name": "Quick Toss",
      "description": "A fast, light throw.",
      "skill_type": "throw",
      "mechanic": "windup",
      "energy_cost": 3,
      "timing": {
        "activation_ms": 0,
        "aftercast_ms": 750,
        "recharge_ms": 1000
      },
      "damage": { "base": 8.0 },
      "targeting": {
        "type": "enemy",
        "range": 180.0,
        "aoe": "single"
      },
      "school_costs": {},
      "effects": [],
      "is_ap": false
    }
  ]
}
```

---

## Runtime Architecture

```
+-------------------------------------------------------------------------+
|                           GAME RUNTIME                                   |
+-------------------------------------------------------------------------+
|                                                                          |
|  +--------------------------------------------------------------------+  |
|  |                        ContentRegistry                              |  |
|  |  +-------------+ +-------------+ +-------------+ +-------------+   |  |
|  |  | SkillTable  | |  GearTable  | | SchoolTable | |PositionTable|   |  |
|  |  | id -> Skill*| | id -> Gear* | | id -> School| |id -> Position   |  |
|  |  +-------------+ +-------------+ +-------------+ +-------------+   |  |
|  |  +-------------+ +-------------+                                    |  |
|  |  | EffectTable | |TerrainTable |                                    |  |
|  |  | id -> Effect| |id -> Terrain|                                    |  |
|  |  +-------------+ +-------------+                                    |  |
|  |                                                                      |  |
|  |  loadPack(pack_blob) -> validates, deserializes, registers          |  |
|  |  getSkill(id) -> *const Skill                                       |  |
|  |  getGear(id) -> *const Gear                                         |  |
|  |  validateBuild(character) -> bool (checks restrictions)             |  |
|  +--------------------------------------------------------------------+  |
|                                                                          |
|  +--------------------------------------------------------------------+  |
|  |                        ContentLoader                                |  |
|  |                                                                      |  |
|  |  loadFromSqlite(db_path) -> ContentRegistry                         |  |
|  |  loadFromNetwork(peer_addr, pack_hash) -> ContentPack               |  |
|  |  loadFromEmbedded() -> ContentRegistry (compile-time fallback)      |  |
|  |  serializePack(ContentPack) -> []u8                                 |  |
|  |  deserializePack([]u8) -> ContentPack                               |  |
|  +--------------------------------------------------------------------+  |
|                                                                          |
|  +--------------------------------------------------------------------+  |
|  |                        ContentValidator                             |  |
|  |                                                                      |  |
|  |  validateSchema(pack) -> []SchemaError                              |  |
|  |  validateBalance(pack) -> []BalanceWarning                          |  |
|  |  validateReferences(pack, registry) -> []RefError                   |  |
|  |  computeHash(pack) -> [32]u8                                        |  |
|  |  verifySignature(pack, pubkey) -> bool                              |  |
|  +--------------------------------------------------------------------+  |
|                                                                          |
+-------------------------------------------------------------------------+
```

---

## Multiplayer Content Sync

### Match Setup Flow

1. **Host Advertises Match**
   ```
   MatchLobby {
     game_version: "1.2.0",
     required_packs: [
       { type: "skill", id: "core_skills", hash: "abc123" },
       { type: "gear", id: "standard_gear", hash: "def456" },
       ...
     ],
     match_rules: { team_size: 4, mode: "elimination" }
   }
   ```

2. **Client Joins**
   - Check local cache for each required pack hash
   - If missing: try CDN first, fall back to P2P from host
   - Verify integrity: `assert(compute_hash(pack) == expected_hash)`

3. **Character Validation**
   - All clients validate each character against loaded content
   - Check skill IDs exist, gear IDs exist, school valid, position valid
   - Validate build restrictions (AP limit, hand slots, etc.)

4. **Match Starts**
   - All game logic references content by ID
   - Actual data comes from loaded packs
   - State sync only needs IDs, not full definitions

### Host Migration

When host drops:
- New host already has packs (was a client)
- State includes active_skill_effects[] with skill_ids
- Skills are stateless functions - only effects have state
- Seamless transition because all clients have same content

---

## Build Validation

```zig
pub const BuildRestriction = struct {
    max_ap_skills: u8 = 1,
    max_off_school_skills: u8 = 3,
    max_hand_slots: u8 = 2,
    off_position_skill_penalty: f32 = 0.8,  // 20% less effective
};

pub fn validateBuild(character, registry, restrictions) ValidationResult {
    // Check AP skill limit (only 1 allowed)
    // Check hand slots (2-handed items use both)
    // Check school skill compatibility
    // Check position synergies
    // Return list of errors/warnings
}
```

---

## Content Distribution

```
+----------------+     +----------------+     +----------------+
|    Creator     |---->|   Pack CDN     |---->|    Players     |
|   (You/Mod)    |     |   (Optional)   |     |                |
+----------------+     +----------------+     +----------------+
                              |
                       +------+------+
                       | pack_index  |
                       | - manifests |
                       | - signatures|
                       | - changelogs|
                       +-------------+
```

**Distribution Options:**
- **P2P**: Host sends pack to clients on connect (simple, works offline)
- **CDN**: Packs hosted centrally, clients fetch by hash (faster for popular packs)
- **Hybrid**: Try CDN first, fall back to P2P

---

## Designer Workflow

### 1. Edit Content
Use any of:
- SQLite browser (DB Browser for SQLite)
- JSON editor with schema validation
- Custom web UI (future)
- Zig source (compile-time, for official content)

### 2. Validate
```bash
$ snow validate-pack my_skills.json

[OK] Schema validation passed
[OK] All effect references valid
[WARN] Balance warning: "Mega Throw" damage (50) exceeds threshold
[WARN] Balance warning: "Cheap Shot" energy cost (1) very low
[OK] 15 skills validated
```

### 3. Test
```bash
$ snow test-pack my_skills.json --simulations 1000

Running 1000 simulated matches...
Win rates by school:
  Private School: 22% (expected 20%)
  Public School: 18% (expected 20%) [WARN] underperforming
  Montessori: 21%
  Homeschool: 19%
  Waldorf: 20%

Most picked skills:
  1. Quick Toss (89% of builds)
  2. Dodge Roll (76%)
  ...
```

### 4. Publish
```bash
$ snow publish-pack my_skills.json --sign

Pack: my_custom_skills@1.0.0
Hash: sha256:7f83b1657ff1fc53b92dc18148a1d65dfc2d4b1fa3d677284...
Signed: yes (key: togmund@snow.dev)

Upload to CDN? [y/N] y
[OK] Published to cdn.snow.game/packs/7f83b165...
```

---

## Versioning Strategy

### Option A: Semantic Versioning per Pack
```
"FrostMage Skills v1.2.3"
- Major: breaking changes (skill removed, mechanic fundamentally changed)
- Minor: new skills added, balance tweaks
- Patch: bug fixes, typo fixes
```

### Option B: Content-Addressable (like Git)
```
Pack = hash(all_skill_hashes)
Skill = hash(skill_definition)

Players reference: pack@abc123 (immutable)
New version = new hash
```

**Recommendation:** Use both. Semantic version for human readability, content hash for integrity verification.

---

## Content History & Versioning

Track every change to every piece of content. Like Git, but for game content.

### Why Track History?

1. **Balance iteration**: See what changed between patches, revert bad changes
2. **Blame/audit**: Who changed this skill and why?
3. **Time travel**: Play on an older version of a skill pack
4. **Diff/compare**: What's different between v1.2 and v1.3?
5. **Changelogs**: Auto-generate patch notes from history

### Database Schema for History

```sql
-- Every version of every skill ever saved
CREATE TABLE skill_versions (
    id INTEGER PRIMARY KEY,
    skill_id TEXT NOT NULL,            -- Stable identifier ("quick_toss")
    content_hash TEXT NOT NULL,        -- SHA256 of this version's data
    version_number INTEGER NOT NULL,   -- Auto-incrementing per skill_id
    
    -- The actual skill data at this version
    name TEXT NOT NULL,
    description TEXT,
    skill_type TEXT NOT NULL,
    mechanic TEXT NOT NULL,
    energy_cost INTEGER,
    timing_data TEXT,                  -- JSON
    damage_data TEXT,                  -- JSON
    targeting_data TEXT,               -- JSON
    effects_refs TEXT,                 -- JSON array of effect_ids
    school_costs TEXT,                 -- JSON
    is_ap BOOLEAN DEFAULT FALSE,
    full_data TEXT,                    -- Complete JSON snapshot
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    author TEXT,
    commit_message TEXT,               -- "Reduced damage from 25 to 20"
    parent_version_id INTEGER REFERENCES skill_versions(id),
    
    UNIQUE(skill_id, version_number),
    UNIQUE(content_hash)               -- Content-addressable
);

-- Same pattern for effects
CREATE TABLE effect_versions (
    id INTEGER PRIMARY KEY,
    effect_id TEXT NOT NULL,
    content_hash TEXT NOT NULL,
    version_number INTEGER NOT NULL,
    
    name TEXT NOT NULL,
    description TEXT,
    timing TEXT NOT NULL,
    target TEXT NOT NULL,
    condition TEXT DEFAULT 'always',
    modifiers TEXT NOT NULL,           -- JSON
    duration_ms INTEGER NOT NULL,
    is_buff BOOLEAN NOT NULL,
    max_stacks INTEGER DEFAULT 0,
    stack_behavior TEXT DEFAULT 'refresh_duration',
    chain_refs TEXT,                   -- JSON: {on_end, on_removed_early, initial}
    full_data TEXT,
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    author TEXT,
    commit_message TEXT,
    parent_version_id INTEGER REFERENCES effect_versions(id),
    
    UNIQUE(effect_id, version_number),
    UNIQUE(content_hash)
);

-- Same pattern for gear, schools, positions...

-- Current "HEAD" pointer - which version is active
CREATE TABLE content_head (
    id INTEGER PRIMARY KEY,
    content_type TEXT NOT NULL,        -- 'skill', 'effect', 'gear', etc.
    content_id TEXT NOT NULL,          -- 'quick_toss', 'soaked_through', etc.
    current_version_id INTEGER NOT NULL,
    
    UNIQUE(content_type, content_id)
);

-- Tags/releases - named points in history
CREATE TABLE content_tags (
    id INTEGER PRIMARY KEY,
    tag_name TEXT NOT NULL,            -- "v1.2.0", "pre-nerf", "tournament-legal"
    content_type TEXT NOT NULL,
    content_id TEXT NOT NULL,
    version_id INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    author TEXT,
    
    UNIQUE(tag_name, content_type, content_id)
);

-- Branches for experimental changes
CREATE TABLE content_branches (
    id INTEGER PRIMARY KEY,
    branch_name TEXT NOT NULL,         -- "main", "experimental", "tournament"
    content_type TEXT NOT NULL,
    content_id TEXT NOT NULL,
    head_version_id INTEGER NOT NULL,
    
    UNIQUE(branch_name, content_type, content_id)
);
```

### API for Version Operations

```zig
const ContentHistory = struct {
    db: *sqlite.Database,
    
    // Save a new version of a skill
    pub fn commitSkill(
        self: *ContentHistory,
        skill_id: []const u8,
        skill_data: SkillData,
        author: []const u8,
        message: []const u8,
    ) !ContentHash {
        const hash = computeHash(skill_data);
        const parent = try self.getCurrentVersion("skill", skill_id);
        
        try self.db.exec(
            \\INSERT INTO skill_versions 
            \\(skill_id, content_hash, version_number, ..., author, commit_message, parent_version_id)
            \\VALUES (?, ?, ?, ..., ?, ?, ?)
        , .{skill_id, hash, parent.version + 1, ..., author, message, parent.id});
        
        // Update HEAD
        try self.updateHead("skill", skill_id, new_version_id);
        
        return hash;
    }
    
    // Get a specific version
    pub fn getSkillVersion(
        self: *ContentHistory,
        skill_id: []const u8,
        version: VersionRef,  // .head, .number(5), .hash("abc123"), .tag("v1.2.0")
    ) !SkillData {
        const version_id = switch (version) {
            .head => try self.getHead("skill", skill_id),
            .number => |n| try self.getByNumber("skill", skill_id, n),
            .hash => |h| try self.getByHash("skill", h),
            .tag => |t| try self.getByTag("skill", skill_id, t),
        };
        return try self.loadSkillVersion(version_id);
    }
    
    // Get history log
    pub fn getSkillHistory(
        self: *ContentHistory,
        skill_id: []const u8,
        limit: u32,
    ) ![]VersionInfo {
        return try self.db.query(
            \\SELECT version_number, content_hash, author, commit_message, created_at
            \\FROM skill_versions
            \\WHERE skill_id = ?
            \\ORDER BY version_number DESC
            \\LIMIT ?
        , .{skill_id, limit});
    }
    
    // Diff two versions
    pub fn diffSkill(
        self: *ContentHistory,
        skill_id: []const u8,
        from_version: VersionRef,
        to_version: VersionRef,
    ) !SkillDiff {
        const old = try self.getSkillVersion(skill_id, from_version);
        const new = try self.getSkillVersion(skill_id, to_version);
        return computeDiff(old, new);
    }
    
    // Revert to a previous version
    pub fn revertSkill(
        self: *ContentHistory,
        skill_id: []const u8,
        to_version: VersionRef,
        author: []const u8,
    ) !ContentHash {
        const old_data = try self.getSkillVersion(skill_id, to_version);
        return try self.commitSkill(
            skill_id, 
            old_data, 
            author, 
            std.fmt.allocPrint("Revert to version {}", .{to_version})
        );
    }
    
    // Tag a version
    pub fn tagVersion(
        self: *ContentHistory,
        content_type: []const u8,
        content_id: []const u8,
        version: VersionRef,
        tag_name: []const u8,
    ) !void {
        const version_id = try self.resolveVersion(content_type, content_id, version);
        try self.db.exec(
            "INSERT INTO content_tags (tag_name, content_type, content_id, version_id) VALUES (?, ?, ?, ?)",
            .{tag_name, content_type, content_id, version_id}
        );
    }
};

pub const VersionRef = union(enum) {
    head,                    // Current version
    number: u32,             // Version 5
    hash: []const u8,        // By content hash
    tag: []const u8,         // By tag name ("v1.2.0")
    branch: []const u8,      // By branch name ("experimental")
};
```

### CLI for History Operations

```bash
# View history of a skill
$ snow history skill quick_toss

Version  Hash      Author    Date        Message
─────────────────────────────────────────────────────────────
7        a1b2c3    togmund   2024-01-20  Reduce aftercast from 750ms to 600ms
6        d4e5f6    togmund   2024-01-15  Increase energy cost 3 -> 4
5        g7h8i9    togmund   2024-01-10  Add conditional damage vs chilled
4        j0k1l2    togmund   2024-01-05  Initial implementation
...

# Show diff between versions
$ snow diff skill quick_toss --from 5 --to 7

quick_toss:
  energy_cost: 3 -> 4
  timing.aftercast_ms: 750 -> 600
  effects: + conditional_chill_damage

# Revert a skill
$ snow revert skill quick_toss --to 5 --message "v6 nerf was too harsh"

Reverted quick_toss to version 5
New version: 8 (hash: m3n4o5)

# Tag current versions for a release
$ snow tag v1.2.0 --all

Tagged 45 skills, 28 effects, 12 gear items as v1.2.0

# Load a specific historical version for testing
$ snow run --skill-version quick_toss@5

Loading quick_toss at version 5 (hash: g7h8i9)
```

### Pack Snapshots

A pack is a snapshot of multiple content items at specific versions:

```sql
-- A pack is a collection of content at specific versions
CREATE TABLE pack_contents (
    id INTEGER PRIMARY KEY,
    pack_id INTEGER REFERENCES content_packs(id),
    content_type TEXT NOT NULL,        -- 'skill', 'effect', etc.
    content_id TEXT NOT NULL,          -- 'quick_toss'
    version_id INTEGER NOT NULL,       -- Specific version included
    
    UNIQUE(pack_id, content_type, content_id)
);
```

```json
{
  "pack_id": "core_skills",
  "version": "1.2.0",
  "content_hash": "sha256:abc123...",
  "contents": [
    { "type": "skill", "id": "quick_toss", "version": 7, "hash": "a1b2c3" },
    { "type": "skill", "id": "power_throw", "version": 4, "hash": "x9y8z7" },
    { "type": "effect", "id": "soaked_through", "version": 2, "hash": "p5q6r7" },
    ...
  ]
}
```

### Use Cases

**Balance Iteration:**
```bash
# Check what changed when a skill became OP
$ snow history skill ice_barrage --since "2024-01-01"
$ snow diff skill ice_barrage --from v1.1.0 --to v1.2.0

# Found it - revert just that skill
$ snow revert skill ice_barrage --to v1.1.0
```

**Tournament Play:**
```bash
# Create a stable tournament version
$ snow tag tournament-season-3 --all
$ snow export-pack --tag tournament-season-3 -o tournament_s3.json

# Players load tournament pack
$ snow run --pack tournament_s3.json
```

**A/B Testing:**
```bash
# Create experimental branch
$ snow branch create experimental
$ snow checkout experimental

# Make changes
$ snow edit skill quick_toss --damage 12
$ snow commit -m "Testing higher quick_toss damage"

# Run simulations on both
$ snow test --branch main --simulations 1000
$ snow test --branch experimental --simulations 1000

# Compare results, merge if good
$ snow merge experimental --into main
```

---

## Developer Workflow: Fast Iteration

During development, you don't want to touch SQLite or JSON files. The current Zig source files (`skills.zig`, `effects.zig`, etc.) remain your fast iteration path.

### The Two Modes

```
┌─────────────────────────────────────────────────────────────┐
│                     DEVELOPMENT MODE                         │
│                                                              │
│   skills.zig ──> compile ──> game                           │
│                                                              │
│   - Edit Zig, hit F5, see changes                           │
│   - Compiler catches type errors                            │
│   - No database, no JSON, no registry                       │
│   - Sub-second iteration loop                               │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                     PRODUCTION MODE                          │
│                                                              │
│   skills.zig ──> export ──> SQLite/JSON ──> distribute      │
│                     │                                        │
│                     └──> content registry ──> game           │
│                                                              │
│   - Content packs for multiplayer sync                      │
│   - Version history in database                             │
│   - Modders edit JSON, not Zig                              │
│   - Runtime content loading                                 │
└─────────────────────────────────────────────────────────────┘
```

### Your Daily Workflow (Dev Mode)

```bash
# 1. Edit skill in your editor
$ vim src/skills.zig
# Change: .damage = 25 → .damage = 30

# 2. Build and run
$ zig build run
# Game launches with new damage value

# 3. Test, tweak, repeat
# Total iteration time: ~2 seconds
```

No content registry. No database. No JSON. Just Zig.

### How This Works

The game has a compile-time flag:

```zig
// src/content_mode.zig
pub const ContentMode = enum {
    embedded,   // Use compile-time Zig definitions (dev mode)
    runtime,    // Load from SQLite/JSON (production mode)
};

// Set at build time
pub const CONTENT_MODE: ContentMode = if (builtin.mode == .Debug)
    .embedded
else
    .runtime;
```

The content registry checks this:

```zig
// src/content_registry.zig
pub fn init(allocator: Allocator) !ContentRegistry {
    return switch (CONTENT_MODE) {
        .embedded => initEmbedded(),   // Just return pointers to comptime data
        .runtime => initRuntime(allocator),  // Load from SQLite
    };
}

fn initEmbedded() ContentRegistry {
    // Zero-cost in dev mode - just wrap the existing comptime arrays
    return .{
        .skills = &skills.ALL_SKILLS,
        .effects = &effects.ALL_EFFECTS,
        .gear = &equipment.ALL_EQUIPMENT,
        // ...
    };
}
```

### When You Need the Full System

The content registry/database matters when:

1. **Exporting for distribution**: `zig build export-content`
2. **Running a multiplayer server**: Clients need to sync content
3. **Testing version history**: Comparing skill versions
4. **Modding**: Others editing your content without Zig

### Export Command

When you're ready to publish:

```bash
# Export current Zig definitions to content pack
$ zig build export-content

Exporting content from Zig source...
  Skills: 147 exported
  Effects: 89 exported
  Gear: 45 exported
  Schools: 5 exported
  Positions: 6 exported

Output: content/core_pack_v1.2.0.json
Hash: sha256:abc123...

# Optionally commit to SQLite with history
$ zig build export-content -- --to-sqlite --message "Balance pass: reduced Quick Toss damage"
```

### Hot Reload (Optional Future Feature)

For even faster iteration, add hot reload in dev mode:

```zig
// Watch skills.zig for changes, recompile just that module
$ zig build run -- --hot-reload

[HOT RELOAD] skills.zig changed, reloading...
[HOT RELOAD] 147 skills reloaded in 0.3s
```

But honestly, Zig compiles so fast that full rebuilds are fine for most iteration.

### Summary: When to Use What

| Task | Method | Speed |
|------|--------|-------|
| Tweak a number | Edit Zig, rebuild | ~2 sec |
| Add a new skill | Edit Zig, rebuild | ~2 sec |
| Test balance changes | Edit Zig, run simulation | ~5 sec |
| Export for multiplayer | `zig build export-content` | ~1 sec |
| View version history | SQLite queries | N/A |
| Mod the game (non-dev) | Edit JSON, reload | ~1 sec |

**The content system is for distribution, not development.**

---

Like MTG Cube drafts, tournament organizers can create custom rulesets by cherry-picking content from multiple packs.

### The Problem

You have 5 content packs available:
- `core` - Base game skills, gear, effects
- `winter_expansion` - New winter-themed content
- `competitive` - Tournament-balanced versions of skills
- `silly_mode` - Joke skills, ridiculous gear
- `community_picks` - Fan-favorite community creations

A tournament organizer wants to:
1. Use most of `core`, but ban 3 overpowered skills
2. Include the `competitive` version of "Ice Barrage" (not the `core` version)
3. Add 5 specific skills from `winter_expansion`
4. Exclude all of `silly_mode`
5. Restrict to 2 specific schools

### Server Config: The "Cube" File

```toml
# tournament_config.toml
# A curated "cube" for the Winter Championship 2024

[meta]
name = "Winter Championship 2024"
description = "Balanced competitive format with winter expansion picks"
author = "FrostyTournaments"
version = "1.0.0"
created = "2024-01-15"

# Base content - start with these packs
[sources]
base_packs = [
    "core@1.2.0",           # Pin to specific version
    "competitive@2.0.0",
]

# What's allowed in this cube
[content]

# Skills: whitelist mode (only these skills allowed)
# If omitted, defaults to "all from base_packs"
[content.skills]
mode = "whitelist"  # or "blacklist"
include = [
    # All core skills except banned ones
    "core:*",
    # Cherry-pick from winter expansion
    "winter_expansion:frost_nova",
    "winter_expansion:blizzard",
    "winter_expansion:ice_wall",
    "winter_expansion:snowdrift",
    "winter_expansion:avalanche",
]
exclude = [
    # Banned for balance
    "core:mega_throw",
    "core:infinite_energy",
    "core:instant_win",
]
# Override: use competitive version instead of core
overrides = [
    { id = "ice_barrage", use = "competitive:ice_barrage" },
    { id = "power_throw", use = "competitive:power_throw" },
]

# Gear: blacklist mode (everything except these)
[content.gear]
mode = "blacklist"
exclude = [
    "core:debug_helmet",
    "silly_mode:*",  # Exclude entire pack
]

# Effects: inherit from skills (auto-include referenced effects)
[content.effects]
mode = "auto"  # Automatically include effects referenced by allowed skills

# Schools: only allow these
[content.schools]
mode = "whitelist"
include = [
    "core:public_school",
    "core:private_school",
    "core:montessori",
    # No Homeschool or Waldorf in this format
]

# Positions: all allowed
[content.positions]
mode = "all"

# Build restrictions for this tournament
[rules]
max_skills = 8
max_ap_skills = 1
max_off_school_skills = 2
team_size = 4
match_format = "best_of_3"
time_limit_seconds = 600

# Skill slot restrictions (optional)
[rules.skill_slots]
# Slot 0 must be a throw skill
0 = { type = "throw" }
# Slot 7 must be your AP skill (if you have one)
7 = { type = "ap", optional = true }

# School-specific restrictions
[rules.school_restrictions]
# Private school players can only use 1 off-school skill (normally 2)
private_school = { max_off_school = 1 }

# Draft rules (if this is a draft format)
[draft]
enabled = true
format = "snake"           # snake, rotating, or auction
picks_per_player = 8
ban_phase = true
bans_per_team = 2
shared_pool = false        # true = cube draft, false = each player picks from full pool
```

### Minimal Config (Quick Setup)

For a simple "just ban a few things" tournament:

```toml
# simple_tournament.toml

[meta]
name = "Friday Night Snowball"

[sources]
base_packs = ["core@latest"]

[content.skills]
mode = "blacklist"
exclude = ["core:mega_throw", "core:broken_skill"]

[rules]
team_size = 4
```

That's it. Everything else uses defaults.

### Config Complexity Spectrum

| Complexity | Setup Time | Use Case |
|------------|------------|----------|
| **Minimal** | 2 minutes | "Ban 3 skills, use defaults" |
| **Simple** | 10 minutes | "Pick 2 packs, set team size" |
| **Standard** | 30 minutes | "Custom banlist, some overrides, draft format" |
| **Full Cube** | 1-2 hours | "Hand-pick every skill, custom rules, complex draft" |

### UI for Config Creation

Instead of writing TOML by hand, provide a web UI:

```
┌─────────────────────────────────────────────────────────────┐
│  Create Tournament: Winter Championship 2024                 │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Base Packs:  [x] core v1.2.0                               │
│               [x] competitive v2.0.0                         │
│               [ ] winter_expansion v1.0.0                    │
│               [ ] silly_mode v3.0.0                          │
│                                                              │
│  ─────────────────────────────────────────────────────────  │
│                                                              │
│  Skills (147 available)                    [Search: ____]    │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ [x] Quick Toss (core)              [Standard ▼]      │   │
│  │ [x] Power Throw (core)             [Competitive ▼]   │   │
│  │ [x] Ice Barrage (core)             [Competitive ▼]   │   │
│  │ [ ] Mega Throw (core)              [BANNED]          │   │
│  │ [x] Frost Nova (winter_expansion)  [Standard ▼]      │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  Schools:  [x] Public  [x] Private  [x] Montessori          │
│            [ ] Homeschool  [ ] Waldorf                       │
│                                                              │
│  Rules:    Team Size: [4 ▼]  Format: [Best of 3 ▼]          │
│            Max AP Skills: [1]  Time Limit: [10:00]          │
│                                                              │
│  [Preview Config]  [Test Validation]  [Export TOML]  [Save] │
└─────────────────────────────────────────────────────────────┘
```

### Server Startup with Config

```bash
# Start server with tournament config
$ snow serve --config tournament_config.toml --port 7777

Loading tournament: Winter Championship 2024
  Base packs: core@1.2.0, competitive@2.0.0
  Skills: 142 allowed (3 banned, 2 overridden)
  Gear: 45 allowed (2 excluded)
  Schools: 3 allowed
  Positions: 6 allowed
  
Server ready on port 7777
Invite code: FROST-WINTER-2024
```

### Client Connection Flow

```
1. Client connects to server
2. Server sends: TournamentManifest {
     name: "Winter Championship 2024",
     required_packs: ["core@1.2.0", "competitive@2.0.0"],
     config_hash: "abc123",  // Hash of the cube config
   }
3. Client checks: Do I have these packs? (download if not)
4. Client downloads cube config (small, just the rules)
5. Client applies config locally (filters available content)
6. Client shows character creation with only allowed options
7. Server validates all builds against config before match starts
```

### Config Validation

Before a tournament starts, validate the config makes sense:

```bash
$ snow validate-config tournament_config.toml

[OK] All referenced packs exist
[OK] All skill overrides point to valid skills
[OK] At least 8 skills available (minimum for builds)
[OK] All schools have at least 5 skills
[WARN] Homeschool has 0 skills (school is disabled - intended?)
[OK] All referenced effects are included
[OK] Draft format valid for team size
[OK] Config hash: abc123def456
```

### Sharing Configs

Tournament configs are small (few KB) and shareable:

```bash
# Export for sharing
$ snow export-config tournament_config.toml -o winter_champ.snowcube
# Creates a signed, versioned config file

# Import someone else's config
$ snow import-config winter_champ.snowcube
Imported: Winter Championship 2024
  From: FrostyTournaments (verified)
  Packs needed: core@1.2.0, competitive@2.0.0

# Browse community configs
$ snow browse-configs --tag tournament
1. Winter Championship 2024 (FrostyTournaments) - 4v4 competitive
2. Chaos Mode Showdown (SnowballSteve) - silly_mode enabled
3. Classic Format (OfficialSnow) - core only, no expansions
...
```

### Summary: Setup Effort

| What They Want | Config Complexity | Time |
|----------------|-------------------|------|
| "Just run the game" | No config needed | 0 min |
| "Ban a few broken skills" | 5-line TOML | 2 min |
| "Use these 2 packs, 4v4" | 10-line TOML | 5 min |
| "Full curated tournament" | Web UI | 30 min |
| "Hand-craft every detail" | Full TOML | 1-2 hrs |

The key insight: **make the simple case trivial, and the complex case possible**.

---

1. **Serialization** - Get `Skill`, `Gear`, `School`, `Effect`, `Position` to/from JSON
2. **SQLite storage** - Store/retrieve content packs
3. **Runtime loader** - Replace compile-time content with runtime lookup
4. **Validation** - Schema and basic balance checks
5. **Network sync** - Pack transfer between host/clients
6. **Versioning** - Content-addressed packs with history
7. **Editor UI** - Web or native tool for content editing

---

## Open Questions

- [ ] How do we handle skill balance across different pack combinations?
- [ ] Should position selection restrict school choice or vice versa?
- [ ] How do we handle deprecated/removed content in older saves?
- [ ] What's the maximum pack size before we need streaming/chunked loading?
- [ ] How do we handle mods that conflict with each other?
- [ ] Should position skills be separate from school skills, or can they overlap?
