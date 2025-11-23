# Snow Gear System Design

## Overview
A flexible 6-slot equipment system inspired by GW1 armor mechanics, but simplified for a winter game where any character can wear any gear. Gear progression is driven by **padding values** (defense tier) + **bonus stats** (special effects).

## Gear Slots

| Slot | Light | Medium | Heavy |
|------|-------|--------|-------|
| **Toque** (Head) | Wool Cap (5) | Ski Beanie (10) | Winter Parka Hood (15) |
| **Scarf** (Neck) | Light Scarf (8) | Puffy Scarf (12) | Wool Neck Guard (18) |
| **Jacket** (Torso) | Hoodie (15) | Ski Jacket (25) | Heavy Parka (35) |
| **Gloves** (Hands) | Mittens (10) | Insulated Gloves (15) | Thermal Gauntlets (22) |
| **Pants** (Legs) | Joggers (10) | Snow Pants (20) | Thermal Leggings (28) |
| **Boots** (Feet) | Sneakers (8) | Insulated Boots (15) | Ice Climbing Boots (22) |

## Padding Values (Armor Rating)

**Light padding**: 5-10 per slot → ~30-60 total (takes 100%-183% damage depending on placement)
**Medium padding**: 10-20 per slot → ~60-100 total (takes 50%-120% damage)
**Heavy padding**: 15-35 per slot → ~90-140 total (takes 26%-50% damage)

### Baseline (No Gear)
- Character starts with **0 padding** → takes 283% damage (armor rating = 0)
- Base damage feels threatening

### Light Setup (all light pieces)
- **~45 average padding** → ~80% of base damage
- Quick, mobile playstyle

### Medium Setup (all medium pieces)
- **~80 average padding** → ~50% of base damage (GW1 baseline)
- Balanced

### Heavy Setup (all heavy pieces)
- **~140 average padding** → ~26% of base damage
- Tank playstyle, significant mobility penalty

## Bonus Stats Per Gear Piece

Each piece can add one or more of:
- **Warmth regen** (+1-3/sec per piece)
- **Energy regen** (+0.1-0.3/sec per piece)
- **Movement speed** (±10-20% modifier)
- **Special effects** (immunity to certain conditions, passive bonuses, etc.)

### Example Gear Set: Heavy Parka Set (Tank build)

| Piece | Padding | Warmth Regen | Speed | Special |
|-------|---------|--------------|-------|---------|
| Winter Parka Hood | 15 | +2 | -5% | - |
| Wool Neck Guard | 18 | - | - | - |
| Heavy Parka | 35 | +3 | -10% | - |
| Thermal Gauntlets | 22 | +1 | -5% | - |
| Thermal Leggings | 28 | +2 | -10% | Immunity to Slippery |
| Ice Climbing Boots | 22 | +1 | -15% | +20% up hills |
| **TOTAL** | **140** | **+9/sec** | **-45%** | Tanky, slow, warm |

### Example Gear Set: Light Scout Set (DPS build)

| Piece | Padding | Energy Regen | Speed | Special |
|-------|---------|--------------|-------|---------|
| Wool Cap | 5 | - | - | - |
| Light Scarf | 8 | - | - | - |
| Hoodie | 15 | +0.3 | +5% | - |
| Mittens | 10 | +0.2 | - | - |
| Joggers | 10 | +0.2 | +10% | - |
| Sneakers | 8 | - | +15% | - |
| **TOTAL** | **56** | **+0.7/sec** | **+30%** | Fast, low defense, energy regen |

## Damage Calculation Formula

```
armor_rating = sum(padding values from equipped gear)

// GW1-inspired formula: armor provides percentage-based reduction
// Baseline (60 armor) = 100% damage received
// +40 armor = 50% damage received (halves damage)
damage_multiplier = armor_rating / (armor_rating + 40)

final_damage = base_damage * damage_multiplier

// Armor penetration (for skills with penetrate property)
effective_armor = armor_rating * (1 - penetration_percent)
final_damage = base_damage * (effective_armor / (effective_armor + 40))
```

### Examples

- **0 padding**: `0 / (0 + 40) = 0` → 1x damage (takes full damage, unarmored)
- **40 padding**: `40 / (40 + 40) = 0.5` → 0.5x damage (takes 50%, good defense)
- **80 padding**: `80 / (80 + 40) = 0.667` → 0.667x damage (takes 67%, solid tank)
- **140 padding**: `140 / (140 + 40) = 0.778` → 0.778x damage (takes 78%, barely worth it above this)

Wait, I think you meant I got this backwards - let me recalculate:

Actually in GW1:
- **60 armor** = baseline (damage multiplier = 1.0, normal damage)
- **100 armor** = `100 / (100 + 40) = 0.5` → takes 0.5x damage (BLOCKED 50%)
- **0 armor** = `0 / (0 + 40) = 0` → takes 0 damage (full block???)

Let me use the GW1 armor rating formula correctly:
- Every 40 armor difference = 2x damage difference
- Formula from wiki: damage taken = `base_damage / (1 + armor/40)`

OR simpler: `damage_reduction = armor / (armor + 40)`
- 0 armor → 0% reduction (takes 100% damage)
- 40 armor → 50% reduction (takes 50% damage)
- 80 armor → 67% reduction (takes 33% damage)
- 100 armor → 71% reduction (takes 29% damage)

So: `final_damage = base_damage * (1 - armor / (armor + 40))`

### Corrected Examples

- **0 padding**: `1 - 0/(0+40) = 1.0` → **100% damage taken** (unarmored)
- **40 padding**: `1 - 40/(40+40) = 0.5` → **50% damage taken** (half damage)
- **80 padding**: `1 - 80/(80+40) = 0.333` → **33% damage taken** (two-thirds blocked)
- **140 padding**: `1 - 140/(140+40) = 0.222` → **22% damage taken** (tanks!)

## Implementation Plan

1. **Create `gear_slot.zig`**: Enum for 6 slots + gear definitions
2. **Create gear pieces** with padding + bonus stats
3. **Update `Character` struct**: Add 6 gear slots (replace main_hand/off_hand/worn)
4. **Implement `getTotalPadding()`**: Sum all equipped gear padding
5. **Update `combat.zig`**: Apply armor reduction to damage calculation
6. **Add visual gear display**: Render equipped gear on character model

## Bonus Stat Applications (Future TODOs)

- Warmth regen: Add to character's `recalculateWarmthPips()`
- Energy regen: Add to character's `updateEnergy()`
- Speed modifier: Multiply movement speed calculations
- Special effects: Apply as conditions or modify skill behavior
