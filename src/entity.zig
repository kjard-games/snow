// Entity ID system for stable entity references in tick-based multiplayer
//
// In tab-targeting games, entities are referenced by ID, not array index.
// This allows:
// - Stable references across ticks (entities can die/respawn)
// - Network replication (client and server use same IDs)
// - Target selection that survives entity reordering

const std = @import("std");

/// Unique identifier for an entity in the game world
/// In multiplayer, these IDs are assigned by the server
pub const EntityId = u32;

/// Special ID value representing "no entity"
pub const NULL_ENTITY: EntityId = 0;

/// Team identifier for multi-team gameplay
/// Supports 2+ team scenarios (GvG, FFA, 2v2v2v2, etc.)
pub const Team = enum(u8) {
    none = 0, // Neutral/environment entities
    red = 1, // Team 1 (ally team in standard 4v4)
    blue = 2, // Team 2 (enemy team in standard 4v4)
    yellow = 3, // Team 3 (for multi-team modes)
    green = 4, // Team 4 (for multi-team modes)

    /// Check if two teams are allied
    pub fn isAlly(self: Team, other: Team) bool {
        if (self == .none or other == .none) return false;
        return self == other;
    }

    /// Check if two teams are enemies
    pub fn isEnemy(self: Team, other: Team) bool {
        if (self == .none or other == .none) return false;
        return self != other;
    }
};

/// ID generator for local single-player (in multiplayer, server assigns IDs)
pub const EntityIdGenerator = struct {
    next_id: EntityId = 1, // Start at 1 (0 is NULL_ENTITY)

    pub fn generate(self: *EntityIdGenerator) EntityId {
        const id = self.next_id;
        self.next_id += 1;
        return id;
    }

    pub fn reset(self: *EntityIdGenerator) void {
        self.next_id = 1;
    }
};
