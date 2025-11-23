const std = @import("std");
const terrain = @import("src/terrain.zig");

pub fn main() !void {
    const types = [_]terrain.TerrainType{
        .deep_powder,
        .thick_snow,
        .packed_snow,
        .icy_ground,
        .slushy,
        .cleared_ground,
    };
    
    std.debug.print("Terrain type colors:\n", .{});
    for (types) |t| {
        const color = t.getColor();
        std.debug.print("  {s}: RGB({d}, {d}, {d})\n", .{
            @tagName(t),
            color.r,
            color.g,
            color.b,
        });
    }
}
