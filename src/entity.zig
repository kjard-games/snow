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
