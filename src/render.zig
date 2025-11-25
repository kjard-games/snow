const std = @import("std");
const rl = @import("raylib");
const character = @import("character.zig");
const entity_types = @import("entity.zig");
const vfx = @import("vfx.zig");
const palette = @import("color_palette.zig");
const terrain = @import("terrain.zig");
const ground_targeting = @import("ground_targeting.zig");

const Character = character.Character;
const EntityId = entity_types.EntityId;
const TerrainGrid = terrain.TerrainGrid;
const GroundTargetingState = ground_targeting.GroundTargetingState;

// Rendering constants - organized by category for clarity
const skybox = struct {
    const radius: f32 = 3000.0;
    const top_offset: f32 = 500.0;
    const horizon_offset: f32 = -200.0;
};

const mountain = struct {
    const distance: f32 = 2500.0;
    const base_height: f32 = 300.0;
    const height_variation: f32 = 150.0;
    const count: usize = 8;
};

const terrain_rendering = struct {
    const base_y: f32 = -30.0;
};

const ui = struct {
    const element_offset_y: f32 = 10.0;
    const bar_width: i32 = 80;
    const bar_height: i32 = 8;
};

const selection = struct {
    const ring_offset: f32 = 5.0;
    const arrow_offset: f32 = 15.0;
    const arrow_size: f32 = 5.0;
};

const outline = struct {
    const thickness: f32 = 3.0;
};

// Team outline shader system
pub var outline_render_texture: ?rl.RenderTexture2D = null;
pub var outline_shader: ?rl.Shader = null;
var resolution_loc: i32 = 0;
var thickness_loc: i32 = 0;

// Vertex color shader for terrain rendering
var vertex_color_shader: ?rl.Shader = null;
var terrain_material: ?rl.Material = null;
var viewPos_loc: i32 = -1; // Shader uniform location for camera position

/// Initialize the outline shader system for team-based silhouette rendering.
/// Returns an error if shader resources fail to load.
pub fn initOutlineShader(screen_width: i32, screen_height: i32) !void {
    outline_render_texture = try rl.loadRenderTexture(screen_width, screen_height);
    errdefer {
        if (outline_render_texture) |tex| rl.unloadRenderTexture(tex);
        outline_render_texture = null;
    }

    outline_shader = try rl.loadShader("shaders/outline.vs", "shaders/team_outline.fs");

    if (outline_shader) |shader| {
        resolution_loc = rl.getShaderLocation(shader, "resolution");
        thickness_loc = rl.getShaderLocation(shader, "thickness");

        // Set resolution uniform
        const res = [2]f32{ @floatFromInt(screen_width), @floatFromInt(screen_height) };
        rl.setShaderValue(shader, resolution_loc, &res, rl.ShaderUniformDataType.vec2);
    }
}

/// Initialize terrain material with vertex color shader
pub fn initTerrainMaterial() !void {
    vertex_color_shader = try rl.loadShader("shaders/vertex_color.vs", "shaders/vertex_color.fs");
    errdefer {
        if (vertex_color_shader) |shader| rl.unloadShader(shader);
        vertex_color_shader = null;
    }
    terrain_material = try rl.loadMaterialDefault();
    if (vertex_color_shader) |shader| {
        terrain_material.?.shader = shader;
        // Get uniform location for camera position (used for view-dependent snow effects)
        viewPos_loc = rl.getShaderLocation(shader, "viewPos");
    }
}

/// Clean up all render resources (shaders, textures, materials).
/// Safe to call multiple times.
pub fn deinitRenderResources() void {
    if (outline_render_texture) |tex| {
        rl.unloadRenderTexture(tex);
        outline_render_texture = null;
    }
    if (outline_shader) |shader| {
        rl.unloadShader(shader);
        outline_shader = null;
    }
    // Note: vertex_color_shader is NOT manually unloaded here because
    // unloadMaterial will handle freeing the shader attached to the material.
    // Manually unloading it would cause a double-free.
    if (terrain_material) |mat| {
        rl.unloadMaterial(mat);
        terrain_material = null;
    }
    vertex_color_shader = null;
}

/// Handle window resize by recreating render textures and updating shader uniforms.
/// Call this when window size changes to ensure correct outline rendering.
pub fn handleWindowResize(new_width: i32, new_height: i32) void {
    // Recreate outline render texture at new size
    if (outline_render_texture) |tex| {
        rl.unloadRenderTexture(tex);
    }
    outline_render_texture = rl.loadRenderTexture(new_width, new_height) catch {
        std.debug.print("Failed to recreate outline render texture on resize\n", .{});
        outline_render_texture = null;
        return;
    };

    // Update resolution uniform in outline shader
    if (outline_shader) |shader| {
        const res = [2]f32{ @floatFromInt(new_width), @floatFromInt(new_height) };
        rl.setShaderValue(shader, resolution_loc, &res, rl.ShaderUniformDataType.vec2);
    }
}

// Helper to convert float coordinates to integer screen positions
inline fn toScreenPos(pos: rl.Vector2) struct { x: i32, y: i32 } {
    return .{
        .x = @intFromFloat(pos.x),
        .y = @intFromFloat(pos.y),
    };
}

/// Draw a simple atmospheric skybox with winter sky gradient and distant mountains.
fn drawSkybox(camera: rl.Camera) void {
    // Sky color gradient: darker blue-gray at top, lighter blue-white at horizon
    const sky_top = rl.Color{ .r = 120, .g = 140, .b = 180, .a = 255 };
    const sky_horizon = rl.Color{ .r = 200, .g = 210, .b = 230, .a = 255 };

    // Draw back hemisphere (top of sky)
    rl.drawSphereEx(
        rl.Vector3{ .x = camera.position.x, .y = camera.position.y + skybox.top_offset, .z = camera.position.z },
        skybox.radius,
        16, // Lower poly count for performance
        16,
        sky_top,
    );

    // Draw horizon ring
    rl.drawSphereEx(
        rl.Vector3{ .x = camera.position.x, .y = camera.position.y + skybox.horizon_offset, .z = camera.position.z },
        skybox.radius,
        16,
        8,
        sky_horizon,
    );

    // Add distant mountain silhouettes
    const mountain_color = rl.Color{ .r = 90, .g = 100, .b = 120, .a = 200 };

    // Draw peaks around the horizon
    for (0..mountain.count) |i| {
        const angle = @as(f32, @floatFromInt(i)) * std.math.pi * 2.0 / @as(f32, @floatFromInt(mountain.count));
        const height = mountain.base_height + @sin(angle * 3.0) * mountain.height_variation;
        const peak_x = camera.position.x + @cos(angle) * mountain.distance;
        const peak_z = camera.position.z + @sin(angle) * mountain.distance;

        // Draw tapered mountain using cylinder (top radius smaller than bottom)
        rl.drawCylinder(
            rl.Vector3{ .x = peak_x, .y = -50 + height / 2.0, .z = peak_z },
            50.0, // Top radius (small peak)
            200.0, // Bottom radius (wide base)
            height,
            8, // Sides
            mountain_color,
        );
    }
}

/// Draw the terrain grid with 3D snow depth and elevation.
fn drawTerrainGrid(grid: *const TerrainGrid) void {
    var z: usize = 0;
    while (z < grid.height) : (z += 1) {
        var x: usize = 0;
        while (x < grid.width) : (x += 1) {
            const index = z * grid.width + x;
            const cell = grid.cells[index];
            const elevation = grid.heightmap[index];
            const world_pos = grid.gridToWorld(x, z);

            const tile_size = grid.grid_size;
            const color = cell.type.getColor();
            const snow_height = cell.type.getSnowHeight();

            // Draw ground base (dark gray/brown ground underneath snow)
            // Ground extends from elevation down to a fixed base level
            const ground_thickness = elevation - terrain_rendering.base_y;
            const ground_center_y = terrain_rendering.base_y + ground_thickness / 2.0;

            const ground_color = rl.Color{ .r = 80, .g = 70, .b = 60, .a = 255 };
            rl.drawCube(
                rl.Vector3{ .x = world_pos.x, .y = ground_center_y, .z = world_pos.z },
                tile_size,
                ground_thickness,
                tile_size,
                ground_color,
            );

            // Draw snow layer with actual height on top of elevation
            if (snow_height > 0.5) {
                // Snow cube positioned so its bottom is at elevation and top is at elevation + snow_height
                const snow_y = elevation + snow_height / 2.0;
                rl.drawCube(
                    rl.Vector3{ .x = world_pos.x, .y = snow_y, .z = world_pos.z },
                    tile_size - 1.0, // Slightly smaller to show gaps between cells
                    snow_height, // Height based on snow depth
                    tile_size - 1.0,
                    color,
                );

                // Draw top surface highlight (slightly brighter for depth perception)
                var top_color = color;
                top_color.r = @min(255, @as(u16, top_color.r) + 15);
                top_color.g = @min(255, @as(u16, top_color.g) + 15);
                top_color.b = @min(255, @as(u16, top_color.b) + 15);

                rl.drawCube(
                    rl.Vector3{ .x = world_pos.x, .y = elevation + snow_height + 0.1, .z = world_pos.z },
                    tile_size - 1.0,
                    0.2, // Thin top layer
                    tile_size - 1.0,
                    top_color,
                );

                // Draw subtle border on snow edges (darker for contrast)
                var border_color = color;
                border_color.r = @as(u8, @intFromFloat(@as(f32, @floatFromInt(border_color.r)) * 0.6));
                border_color.g = @as(u8, @intFromFloat(@as(f32, @floatFromInt(border_color.g)) * 0.6));
                border_color.b = @as(u8, @intFromFloat(@as(f32, @floatFromInt(border_color.b)) * 0.6));

                rl.drawCubeWires(
                    rl.Vector3{ .x = world_pos.x, .y = snow_y, .z = world_pos.z },
                    tile_size - 1.0,
                    snow_height,
                    tile_size - 1.0,
                    border_color,
                );
            } else {
                // For cleared/icy ground (minimal snow), just draw a thin layer on top of elevation
                rl.drawCube(
                    rl.Vector3{ .x = world_pos.x, .y = elevation + 0.5, .z = world_pos.z },
                    tile_size - 1.0,
                    1.0,
                    tile_size - 1.0,
                    color,
                );
            }

            // Draw wall if present (on top of snow layer)
            if (cell.wall_height > 5.0) {
                const wall_base_y = elevation + snow_height; // Wall sits on top of snow
                const wall_center_y = wall_base_y + cell.wall_height / 2.0;

                // Subtle wall color - blend with snow but slightly darker/tinted
                // Very subtle team tint to distinguish ownership
                var wall_color = rl.Color{ .r = 210, .g = 215, .b = 225, .a = 255 };

                // Apply very subtle team tint (10% influence)
                switch (cell.wall_team) {
                    .red => {
                        wall_color.r = @min(255, @as(u16, wall_color.r) + 15);
                        wall_color.g = if (wall_color.g > 8) wall_color.g - 8 else 0;
                        wall_color.b = if (wall_color.b > 8) wall_color.b - 8 else 0;
                    },
                    .blue => {
                        wall_color.r = if (wall_color.r > 8) wall_color.r - 8 else 0;
                        wall_color.g = if (wall_color.g > 8) wall_color.g - 8 else 0;
                        wall_color.b = @min(255, @as(u16, wall_color.b) + 15);
                    },
                    .yellow => {
                        wall_color.r = @min(255, @as(u16, wall_color.r) + 15);
                        wall_color.g = @min(255, @as(u16, wall_color.g) + 15);
                        wall_color.b = if (wall_color.b > 8) wall_color.b - 8 else 0;
                    },
                    .green => {
                        wall_color.r = if (wall_color.r > 8) wall_color.r - 8 else 0;
                        wall_color.g = @min(255, @as(u16, wall_color.g) + 15);
                        wall_color.b = if (wall_color.b > 8) wall_color.b - 8 else 0;
                    },
                    .none => {}, // Neutral gray
                }

                // Darken wall based on age (older = darker/weathered)
                const age_factor = @min(1.0, cell.wall_age / 30.0); // Max darkening at 30s
                const age_darken = @as(u8, @intFromFloat(20.0 * age_factor));
                wall_color.r = if (wall_color.r > age_darken) wall_color.r - age_darken else 0;
                wall_color.g = if (wall_color.g > age_darken) wall_color.g - age_darken else 0;
                wall_color.b = if (wall_color.b > age_darken) wall_color.b - age_darken else 0;

                // Height-based shading (taller = slightly darker at base)
                const height_shading = @as(u8, @intFromFloat(@min(15.0, cell.wall_height * 0.2)));

                // Draw wall cube (slightly smaller than tile for distinction)
                rl.drawCube(
                    rl.Vector3{ .x = world_pos.x, .y = wall_center_y, .z = world_pos.z },
                    tile_size - 2.0, // Smaller than tile
                    cell.wall_height,
                    tile_size - 2.0,
                    wall_color,
                );

                // Draw top surface (lighter for height perception)
                var wall_top_color = wall_color;
                wall_top_color.r = @min(255, @as(u16, wall_top_color.r) + 20);
                wall_top_color.g = @min(255, @as(u16, wall_top_color.g) + 20);
                wall_top_color.b = @min(255, @as(u16, wall_top_color.b) + 20);

                rl.drawCube(
                    rl.Vector3{ .x = world_pos.x, .y = wall_base_y + cell.wall_height + 0.1, .z = world_pos.z },
                    tile_size - 2.0,
                    0.3, // Thin top cap
                    tile_size - 2.0,
                    wall_top_color,
                );

                // Draw wall edges/wireframe for structure definition
                var wall_edge_color = wall_color;
                const edge_darken = 40 + height_shading;
                wall_edge_color.r = if (wall_edge_color.r > edge_darken) wall_edge_color.r - edge_darken else 0;
                wall_edge_color.g = if (wall_edge_color.g > edge_darken) wall_edge_color.g - edge_darken else 0;
                wall_edge_color.b = if (wall_edge_color.b > edge_darken) wall_edge_color.b - edge_darken else 0;

                rl.drawCubeWires(
                    rl.Vector3{ .x = world_pos.x, .y = wall_center_y, .z = world_pos.z },
                    tile_size - 2.0,
                    cell.wall_height,
                    tile_size - 2.0,
                    wall_edge_color,
                );
            }
        }
    }
}

/// Draw a character's body with split hemispheres showing school and position colors.
fn drawCharacterBody(render_pos: rl.Vector3, radius: f32, school_color: rl.Color, position_color: rl.Color, is_dead: bool) void {
    if (is_dead) {
        rl.drawSphere(render_pos, radius, palette.TEAM.DEAD);
    } else {
        // Draw left hemisphere in school color
        const left_pos = rl.Vector3{
            .x = render_pos.x - radius * 0.25,
            .y = render_pos.y,
            .z = render_pos.z,
        };
        rl.drawSphereEx(left_pos, radius * 0.75, 16, 16, school_color);

        // Draw right hemisphere in position color
        const right_pos = rl.Vector3{
            .x = render_pos.x + radius * 0.25,
            .y = render_pos.y,
            .z = render_pos.z,
        };
        rl.drawSphereEx(right_pos, radius * 0.75, 16, 16, position_color);
    }
}

/// Main 3D rendering function. Draws the game world with interpolated positions for smooth visuals.
/// Uses interpolation_alpha (0.0-1.0) to smoothly render between fixed-timestep game logic updates.
pub fn draw(player: *const Character, entities: []const Character, selected_target: ?EntityId, camera: rl.Camera, interpolation_alpha: f32, vfx_manager: *const vfx.VFXManager, terrain_grid: *const @import("terrain.zig").TerrainGrid, ground_target_state: *const GroundTargetingState) void {
    rl.clearBackground(rl.Color{ .r = 180, .g = 200, .b = 220, .a = 255 }); // Soft winter sky color

    // === 3D RENDERING ===
    rl.beginMode3D(camera);

    // Draw skybox (simple gradient sphere around camera)
    drawSkybox(camera);

    // Draw terrain mesh with vertex colors (GoW-style)
    // Walls are part of the mesh as height displacement (GoW approach)
    if (terrain_grid.terrain_mesh) |mesh| {
        if (terrain_material) |material| {
            // Set camera position for view-dependent snow effects (SSS, sparkles, fresnel)
            if (vertex_color_shader != null and viewPos_loc >= 0) {
                const cam_pos = [3]f32{ camera.position.x, camera.position.y, camera.position.z };
                rl.setShaderValue(vertex_color_shader.?, viewPos_loc, &cam_pos, rl.ShaderUniformDataType.vec3);
            }
            rl.drawMesh(mesh, material, rl.Matrix.identity());
        }
    }

    // Draw entities (interpolated for smooth movement, adjusted for snow depth)
    for (entities) |ent| {
        // Skip dead entities
        if (!ent.isAlive()) continue;

        // Get interpolated position
        var render_pos = ent.getInterpolatedPosition(interpolation_alpha);

        // Adjust Y position based on terrain elevation and sink depth (characters sink into snow)
        const elevation = terrain_grid.getElevationAt(render_pos.x, render_pos.z);
        const sink_depth = terrain_grid.getSinkDepthAt(render_pos.x, render_pos.z);
        const snow_height = terrain_grid.getSnowHeightAt(render_pos.x, render_pos.z);

        // Character's center should be at: elevation + snow_surface - sink_depth + radius
        // Snow surface is at elevation + snow_height, character sinks sink_depth into it
        render_pos.y = elevation + snow_height - sink_depth + ent.radius;

        // Draw character body with halftone effect
        drawCharacterBody(render_pos, ent.radius, ent.school_color, ent.position_color, ent.is_dead);
    }

    // Draw player (interpolated, adjusted for snow depth)
    var player_render_pos = player.*.getInterpolatedPosition(interpolation_alpha);

    // Adjust player Y position based on terrain elevation
    const player_elevation = terrain_grid.getElevationAt(player_render_pos.x, player_render_pos.z);
    const player_sink_depth = terrain_grid.getSinkDepthAt(player_render_pos.x, player_render_pos.z);
    const player_snow_height = terrain_grid.getSnowHeightAt(player_render_pos.x, player_render_pos.z);
    player_render_pos.y = player_elevation + player_snow_height - player_sink_depth + player.*.radius;

    // Draw player body with halftone effect
    drawCharacterBody(player_render_pos, player.*.radius, player.*.school_color, player.*.position_color, player.*.is_dead);

    // Draw target selection indicator
    if (selected_target) |target_id| {
        // Find target by ID
        var target: ?Character = null;
        if (player.*.id == target_id) {
            target = player.*;
        } else {
            for (entities) |ent| {
                if (ent.id == target_id) {
                    target = ent;
                    break;
                }
            }
        }

        if (target) |tgt| {
            // Only draw selection indicator if target is alive
            if (tgt.isAlive()) {
                // Draw selection ring around target (interpolated, adjusted for terrain)
                var target_render_pos = tgt.getInterpolatedPosition(interpolation_alpha);

                // Adjust for terrain elevation and depth (same as entity rendering)
                const target_elevation = terrain_grid.getElevationAt(target_render_pos.x, target_render_pos.z);
                const target_sink_depth = terrain_grid.getSinkDepthAt(target_render_pos.x, target_render_pos.z);
                const target_snow_height = terrain_grid.getSnowHeightAt(target_render_pos.x, target_render_pos.z);
                target_render_pos.y = target_elevation + target_snow_height - target_sink_depth + tgt.radius;

                rl.drawCylinder(target_render_pos, tgt.radius + selection.ring_offset, tgt.radius + selection.ring_offset, 2, 16, palette.TEAM.SELECTION);

                // Draw selection arrow above target
                const arrow_pos = rl.Vector3{
                    .x = target_render_pos.x,
                    .y = target_render_pos.y + tgt.radius + selection.arrow_offset,
                    .z = target_render_pos.z,
                };
                rl.drawCube(arrow_pos, selection.arrow_size, selection.arrow_size, selection.arrow_size, palette.TEAM.SELECTION);
            }
        }
    }

    // Draw visual effects (projectiles, impacts, heal effects)
    vfx_manager.draw3D();

    // Draw ground targeting preview (if active)
    ground_targeting.drawPreview3D(ground_target_state, player, terrain_grid);

    rl.endMode3D();

    // === TEAM OUTLINE SHADER PASS ===
    if (outline_render_texture != null and outline_shader != null) {
        const outline_tex = outline_render_texture.?;
        const shader = outline_shader.?;

        // Render team outline silhouettes to separate texture
        rl.beginTextureMode(outline_tex);
        rl.clearBackground(rl.Color{ .r = 0, .g = 0, .b = 0, .a = 0 });

        rl.beginMode3D(camera);

        // Draw entities as solid team colors
        for (entities) |ent| {
            if (!ent.isAlive()) continue;

            var render_pos = ent.getInterpolatedPosition(interpolation_alpha);
            const elevation = terrain_grid.getElevationAt(render_pos.x, render_pos.z);
            const sink_depth = terrain_grid.getSinkDepthAt(render_pos.x, render_pos.z);
            const snow_height = terrain_grid.getSnowHeightAt(render_pos.x, render_pos.z);
            render_pos.y = elevation + snow_height - sink_depth + ent.radius;

            const team_color = palette.getOutlineColor(ent.team, player.*.team, false);
            rl.drawSphere(render_pos, ent.radius, team_color);
        }

        // Draw player as solid team color
        var player_pos = player.*.getInterpolatedPosition(interpolation_alpha);
        const p_elevation = terrain_grid.getElevationAt(player_pos.x, player_pos.z);
        const p_sink = terrain_grid.getSinkDepthAt(player_pos.x, player_pos.z);
        const p_snow = terrain_grid.getSnowHeightAt(player_pos.x, player_pos.z);
        player_pos.y = p_elevation + p_snow - p_sink + player.*.radius;
        const player_team_color = palette.getOutlineColor(player.*.team, player.*.team, true);
        rl.drawSphere(player_pos, player.*.radius, player_team_color);

        rl.endMode3D();
        rl.endTextureMode();

        // Apply outline shader and draw to screen
        rl.setShaderValue(shader, thickness_loc, &outline.thickness, rl.ShaderUniformDataType.float);

        rl.beginShaderMode(shader);
        rl.drawTextureRec(
            outline_tex.texture,
            rl.Rectangle{
                .x = 0,
                .y = 0,
                .width = @floatFromInt(outline_tex.texture.width),
                .height = -@as(f32, @floatFromInt(outline_tex.texture.height)), // Flip vertically
            },
            rl.Vector2{ .x = 0, .y = 0 },
            rl.Color.white,
        );
        rl.endShaderMode();
    }

    // === 2D RENDERING (names, health bars, cast bars) ===
    const screen_width = rl.getScreenWidth();
    const screen_height = rl.getScreenHeight();

    // Draw floating UI for all entities
    for (entities) |ent| {
        if (!ent.isAlive()) continue;

        var render_pos = ent.getInterpolatedPosition(interpolation_alpha);

        // Adjust for terrain elevation and depth (same as entity rendering)
        const elevation = terrain_grid.getElevationAt(render_pos.x, render_pos.z);
        const sink_depth = terrain_grid.getSinkDepthAt(render_pos.x, render_pos.z);
        const snow_height = terrain_grid.getSnowHeightAt(render_pos.x, render_pos.z);
        render_pos.y = elevation + snow_height - sink_depth + ent.radius;

        // Position above entity
        const ui_3d_pos = rl.Vector3{
            .x = render_pos.x,
            .y = render_pos.y + ent.radius + ui.element_offset_y,
            .z = render_pos.z,
        };
        const ui_2d_pos = rl.getWorldToScreen(ui_3d_pos, camera);

        // Only draw if on screen
        if (ui_2d_pos.x >= 0 and ui_2d_pos.x < @as(f32, @floatFromInt(screen_width)) and
            ui_2d_pos.y >= 0 and ui_2d_pos.y < @as(f32, @floatFromInt(screen_height)))
        {
            const screen_pos = toScreenPos(ui_2d_pos);
            var current_y: i32 = screen_pos.y;

            // Name
            const text_width = rl.measureText(ent.name, 10);
            rl.drawText(ent.name, screen_pos.x - @divTrunc(text_width, 2), current_y, 10, .white);
            current_y += 12;

            // Health bar
            const bar_x = screen_pos.x - @divTrunc(ui.bar_width, 2);

            // Background
            rl.drawRectangle(bar_x, current_y, ui.bar_width, ui.bar_height, rl.Color{ .r = 20, .g = 20, .b = 20, .a = 200 });

            // Health fill
            const health_percent = ent.warmth / ent.max_warmth;
            const fill_width = @as(i32, @intFromFloat(@as(f32, @floatFromInt(ui.bar_width - 2)) * health_percent));
            const health_color = if (player.isEnemy(ent)) rl.Color.red else rl.Color.green;
            rl.drawRectangle(bar_x + 1, current_y + 1, fill_width, ui.bar_height - 2, health_color);

            // Border
            rl.drawRectangleLines(bar_x, current_y, ui.bar_width, ui.bar_height, .white);
            current_y += ui.bar_height + 2;

            // Cast bar (if casting)
            if (ent.cast_state == .activating) {
                const casting_skill = ent.skill_bar[ent.casting_skill_index];
                if (casting_skill) |skill| {
                    const cast_time_total = @as(f32, @floatFromInt(skill.activation_time_ms)) / 1000.0;
                    const progress = 1.0 - (ent.cast_time_remaining / cast_time_total);

                    // Cast bar
                    rl.drawRectangle(bar_x, current_y, ui.bar_width, ui.bar_height, rl.Color{ .r = 20, .g = 20, .b = 20, .a = 200 });
                    const cast_fill_width = @as(i32, @intFromFloat(@as(f32, @floatFromInt(ui.bar_width - 2)) * progress));
                    rl.drawRectangle(bar_x + 1, current_y + 1, cast_fill_width, ui.bar_height - 2, rl.Color.gold);
                    rl.drawRectangleLines(bar_x, current_y, ui.bar_width, ui.bar_height, .white);
                }
            }
        }
    }

    // Draw player floating UI (same style)
    // Note: player_render_pos is already adjusted for terrain in the 3D section above
    const player_ui_3d_pos = rl.Vector3{
        .x = player_render_pos.x,
        .y = player_render_pos.y + player.*.radius + ui.element_offset_y,
        .z = player_render_pos.z,
    };
    const player_ui_2d_pos = rl.getWorldToScreen(player_ui_3d_pos, camera);

    if (player_ui_2d_pos.x >= 0 and player_ui_2d_pos.x < @as(f32, @floatFromInt(screen_width)) and
        player_ui_2d_pos.y >= 0 and player_ui_2d_pos.y < @as(f32, @floatFromInt(screen_height)))
    {
        const screen_pos = toScreenPos(player_ui_2d_pos);
        var current_y: i32 = screen_pos.y;

        // Name (player name in lime)
        const text_width = rl.measureText(player.*.name, 12);
        rl.drawText(player.*.name, screen_pos.x - @divTrunc(text_width, 2), current_y, 12, .lime);
        current_y += 14;

        // Health bar
        const bar_x = screen_pos.x - @divTrunc(ui.bar_width, 2);

        rl.drawRectangle(bar_x, current_y, ui.bar_width, ui.bar_height, rl.Color{ .r = 20, .g = 20, .b = 20, .a = 200 });
        const health_percent = player.*.warmth / player.*.max_warmth;
        const fill_width = @as(i32, @intFromFloat(@as(f32, @floatFromInt(ui.bar_width - 2)) * health_percent));
        rl.drawRectangle(bar_x + 1, current_y + 1, fill_width, ui.bar_height - 2, rl.Color.green);
        rl.drawRectangleLines(bar_x, current_y, ui.bar_width, ui.bar_height, .white);
        current_y += ui.bar_height + 2;

        // Cast bar (if casting)
        if (player.*.cast_state == .activating) {
            const casting_skill = player.*.skill_bar[player.*.casting_skill_index];
            if (casting_skill) |skill| {
                const cast_time_total = @as(f32, @floatFromInt(skill.activation_time_ms)) / 1000.0;
                const progress = 1.0 - (player.*.cast_time_remaining / cast_time_total);

                rl.drawRectangle(bar_x, current_y, ui.bar_width, ui.bar_height, rl.Color{ .r = 20, .g = 20, .b = 20, .a = 200 });
                const cast_fill_width = @as(i32, @intFromFloat(@as(f32, @floatFromInt(ui.bar_width - 2)) * progress));
                rl.drawRectangle(bar_x + 1, current_y + 1, cast_fill_width, ui.bar_height - 2, rl.Color.gold);
                rl.drawRectangleLines(bar_x, current_y, ui.bar_width, ui.bar_height, .white);
            }
        }
    }

    // Draw visual effects 2D overlay (damage numbers)
    vfx_manager.draw2D(camera);

    // Draw ground targeting 2D overlay (skill name, hints)
    ground_targeting.drawPreview2D(ground_target_state, camera);
}
