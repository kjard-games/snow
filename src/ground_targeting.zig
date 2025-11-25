const std = @import("std");
const rl = @import("raylib");
const skills = @import("skills.zig");
const character = @import("character.zig");
const terrain = @import("terrain.zig");
const palette = @import("color_palette.zig");

const Character = character.Character;
const Skill = skills.Skill;
const TerrainGrid = terrain.TerrainGrid;

/// Ground targeting state - tracks active ground-targeting mode
pub const GroundTargetingState = struct {
    /// Is ground targeting mode currently active?
    active: bool = false,

    /// Which skill index is being targeted (0-7)
    skill_index: u8 = 0,

    /// The skill being targeted (cached for quick access)
    skill: ?*const Skill = null,

    /// Current target position (world space, on ground plane y=0)
    target_position: rl.Vector3 = .{ .x = 0, .y = 0, .z = 0 },

    /// Is the current target position valid? (in range, valid terrain, etc.)
    is_valid: bool = false,

    /// Offset from player position (for gamepad/action-cam relative aiming)
    /// This is in polar coordinates: angle relative to camera facing, distance
    aim_angle: f32 = 0.0, // Radians relative to camera angle
    aim_distance: f32 = 50.0, // Distance from player

    /// Start ground targeting for a skill
    pub fn start(self: *GroundTargetingState, index: u8, skill_ptr: *const Skill, player_pos: rl.Vector3, camera_angle: f32) void {
        self.active = true;
        self.skill_index = index;
        self.skill = skill_ptr;
        self.aim_angle = 0.0; // Start aiming forward
        self.aim_distance = @min(skill_ptr.cast_range * 0.6, 80.0); // Start at 60% range or 80 units

        // Calculate initial target position (in front of player)
        self.updateTargetFromAim(player_pos, camera_angle);
    }

    /// Cancel ground targeting
    pub fn cancel(self: *GroundTargetingState) void {
        self.active = false;
        self.skill_index = 0;
        self.skill = null;
        self.is_valid = false;
    }

    /// Update target position from mouse cursor (world raycast)
    pub fn updateTargetFromMouse(self: *GroundTargetingState, player_pos: rl.Vector3, camera: rl.Camera) void {
        const skill = self.skill orelse return;

        const mouse_pos = rl.getMousePosition();
        const ray = rl.getScreenToWorldRay(mouse_pos, camera);

        if (ray.direction.y != 0.0) {
            const t = -ray.position.y / ray.direction.y;
            if (t > 0.0) {
                self.target_position = .{
                    .x = ray.position.x + ray.direction.x * t,
                    .y = 0.0,
                    .z = ray.position.z + ray.direction.z * t,
                };

                // Check range validity
                const dx = self.target_position.x - player_pos.x;
                const dz = self.target_position.z - player_pos.z;
                const distance = @sqrt(dx * dx + dz * dz);

                self.is_valid = distance <= skill.cast_range;

                // Clamp to max range if out of range
                if (distance > skill.cast_range) {
                    const scale = skill.cast_range / distance;
                    self.target_position.x = player_pos.x + dx * scale;
                    self.target_position.z = player_pos.z + dz * scale;
                }
            }
        }
    }

    /// Update target position from gamepad/action-cam aim (relative to player)
    pub fn updateTargetFromAim(self: *GroundTargetingState, player_pos: rl.Vector3, camera_angle: f32) void {
        const skill = self.skill orelse return;

        // Calculate world-space angle from camera angle + aim offset
        const world_angle = camera_angle + self.aim_angle;

        // Calculate target position
        self.target_position = .{
            .x = player_pos.x + @sin(world_angle) * self.aim_distance,
            .y = 0.0,
            .z = player_pos.z + @cos(world_angle) * self.aim_distance,
        };

        // Check if in range
        self.is_valid = self.aim_distance <= skill.cast_range;
    }

    /// Adjust aim with gamepad stick input
    pub fn adjustAim(self: *GroundTargetingState, stick_x: f32, stick_y: f32, camera_angle: f32, player_pos: rl.Vector3) void {
        const skill = self.skill orelse return;

        // Sensitivity for aim adjustment
        const angle_speed: f32 = 0.08; // Radians per frame at full stick
        const distance_speed: f32 = 3.0; // Units per frame at full stick

        // Apply deadzone
        const deadzone: f32 = 0.15;
        const adjusted_x = if (@abs(stick_x) > deadzone) stick_x else 0.0;
        const adjusted_y = if (@abs(stick_y) > deadzone) stick_y else 0.0;

        // Rotate aim angle (left/right stick)
        self.aim_angle += adjusted_x * angle_speed;

        // Adjust distance (forward/back stick)
        self.aim_distance -= adjusted_y * distance_speed;
        self.aim_distance = @max(20.0, @min(skill.cast_range, self.aim_distance));

        // Update target position
        self.updateTargetFromAim(player_pos, camera_angle);
    }
};

/// Preview shape type (derived from skill properties)
pub const PreviewShape = enum {
    circle, // AoE skills (radius)
    wall, // Wall-building skills (length x thickness)
    line, // Line/cone skills
    cone, // Cone-shaped AoE
};

/// Get the preview shape for a skill
pub fn getPreviewShape(skill: *const Skill) PreviewShape {
    if (skill.creates_wall) {
        return .wall;
    }

    return switch (skill.terrain_effect.shape) {
        .none, .circle, .ring => .circle,
        .line, .trail => .line,
        .cone => .cone,
        .square, .cross => .circle, // Fallback to circle for now
    };
}

/// Draw the ground targeting preview (3D, call within beginMode3D)
pub fn drawPreview3D(state: *const GroundTargetingState, player: *const Character, terrain_grid: *const TerrainGrid) void {
    if (!state.active) return;

    const skill = state.skill orelse return;

    // Colors for valid/invalid targeting
    const valid_color = rl.Color{ .r = 50, .g = 200, .b = 50, .a = 120 }; // Green, semi-transparent
    const invalid_color = rl.Color{ .r = 200, .g = 50, .b = 50, .a = 120 }; // Red, semi-transparent
    const outline_color = if (state.is_valid)
        rl.Color{ .r = 100, .g = 255, .b = 100, .a = 255 }
    else
        rl.Color{ .r = 255, .g = 100, .b = 100, .a = 255 };

    const fill_color = if (state.is_valid) valid_color else invalid_color;

    // Get terrain height at target position
    const target_y = terrain_grid.getGroundYAt(state.target_position.x, state.target_position.z) + 1.0;

    const shape = getPreviewShape(skill);

    switch (shape) {
        .circle => {
            const radius = skill.aoe_radius;
            if (radius > 0) {
                // Draw filled circle on ground
                drawGroundCircle(state.target_position.x, target_y, state.target_position.z, radius, fill_color, 32);
                // Draw outline
                drawGroundCircleOutline(state.target_position.x, target_y, state.target_position.z, radius, outline_color, 32);
            } else {
                // No radius specified, draw a small indicator
                drawGroundCircle(state.target_position.x, target_y, state.target_position.z, 10.0, fill_color, 16);
                drawGroundCircleOutline(state.target_position.x, target_y, state.target_position.z, 10.0, outline_color, 16);
            }
        },

        .wall => {
            // Draw wall preview (arc perpendicular to caster, at target position)
            const dx = state.target_position.x - player.position.x;
            const dz = state.target_position.z - player.position.z;
            const facing_angle = std.math.atan2(dz, dx);

            // Wall is placed at target position (ground-targeted)
            const wall_y = terrain_grid.getGroundYAt(state.target_position.x, state.target_position.z);

            drawArcWallPreview(
                state.target_position.x,
                wall_y,
                state.target_position.z,
                facing_angle,
                skill.wall_length,
                skill.wall_height,
                skill.wall_thickness,
                skill.wall_arc_factor,
                fill_color,
                outline_color,
            );
        },

        .line => {
            // Draw line from player to target
            const player_y = terrain_grid.getGroundYAt(player.position.x, player.position.z) + 1.0;

            rl.drawLine3D(
                .{ .x = player.position.x, .y = player_y, .z = player.position.z },
                .{ .x = state.target_position.x, .y = target_y, .z = state.target_position.z },
                outline_color,
            );

            // Draw endpoint circle
            drawGroundCircle(state.target_position.x, target_y, state.target_position.z, 15.0, fill_color, 16);
            drawGroundCircleOutline(state.target_position.x, target_y, state.target_position.z, 15.0, outline_color, 16);
        },

        .cone => {
            // Draw cone preview
            const dx = state.target_position.x - player.position.x;
            const dz = state.target_position.z - player.position.z;
            const facing_angle = std.math.atan2(dz, dx);

            drawConePreview(
                player.position.x,
                target_y,
                player.position.z,
                facing_angle,
                skill.aoe_radius,
                std.math.pi / 3.0, // 60 degree cone
                fill_color,
                outline_color,
            );
        },
    }

    // Draw range indicator circle around player
    const player_y = terrain_grid.getGroundYAt(player.position.x, player.position.z) + 0.5;
    const range_color = rl.Color{ .r = 150, .g = 150, .b = 150, .a = 80 };
    drawGroundCircleOutline(player.position.x, player_y, player.position.z, skill.cast_range, range_color, 48);

    // Draw targeting line from player to target
    rl.drawLine3D(
        .{ .x = player.position.x, .y = player_y, .z = player.position.z },
        .{ .x = state.target_position.x, .y = target_y, .z = state.target_position.z },
        rl.Color{ .r = 255, .g = 255, .b = 255, .a = 100 },
    );
}

/// Draw the ground targeting UI (2D overlay)
pub fn drawPreview2D(state: *const GroundTargetingState, camera: rl.Camera) void {
    if (!state.active) return;

    const skill = state.skill orelse return;

    // Draw skill name at cursor/reticle position
    const screen_pos = rl.getWorldToScreen(state.target_position, camera);

    const screen_width = rl.getScreenWidth();
    const screen_height = rl.getScreenHeight();

    // Only draw if on screen
    if (screen_pos.x >= 0 and screen_pos.x < @as(f32, @floatFromInt(screen_width)) and
        screen_pos.y >= 0 and screen_pos.y < @as(f32, @floatFromInt(screen_height)))
    {
        const x: i32 = @intFromFloat(screen_pos.x);
        const y: i32 = @intFromFloat(screen_pos.y);

        // Draw skill name
        const text_width = rl.measureText(skill.name, 14);
        rl.drawText(skill.name, x - @divTrunc(text_width, 2), y + 20, 14, .white);

        // Draw "Click to place" or "Press A to confirm" hint
        const hint = "Click/A to place, RMB/B to cancel";
        const hint_width = rl.measureText(hint, 10);
        rl.drawText(hint, x - @divTrunc(hint_width, 2), y + 38, 10, rl.Color{ .r = 200, .g = 200, .b = 200, .a = 255 });

        // Draw validity indicator
        if (!state.is_valid) {
            rl.drawText("OUT OF RANGE", x - 40, y - 20, 12, rl.Color.red);
        }
    }
}

// ============================================================================
// Helper drawing functions
// ============================================================================

/// Draw a filled circle on the ground (horizontal plane)
fn drawGroundCircle(x: f32, y: f32, z: f32, radius: f32, color: rl.Color, segments: u32) void {
    const seg_f = @as(f32, @floatFromInt(segments));
    const angle_step = std.math.pi * 2.0 / seg_f;

    var i: u32 = 0;
    while (i < segments) : (i += 1) {
        const angle1 = @as(f32, @floatFromInt(i)) * angle_step;
        const angle2 = @as(f32, @floatFromInt(i + 1)) * angle_step;

        // Triangle from center to edge
        rl.drawTriangle3D(
            .{ .x = x, .y = y, .z = z },
            .{ .x = x + @cos(angle1) * radius, .y = y, .z = z + @sin(angle1) * radius },
            .{ .x = x + @cos(angle2) * radius, .y = y, .z = z + @sin(angle2) * radius },
            color,
        );
    }
}

/// Draw a circle outline on the ground
fn drawGroundCircleOutline(x: f32, y: f32, z: f32, radius: f32, color: rl.Color, segments: u32) void {
    const seg_f = @as(f32, @floatFromInt(segments));
    const angle_step = std.math.pi * 2.0 / seg_f;

    var i: u32 = 0;
    while (i < segments) : (i += 1) {
        const angle1 = @as(f32, @floatFromInt(i)) * angle_step;
        const angle2 = @as(f32, @floatFromInt((i + 1) % segments)) * angle_step;

        rl.drawLine3D(
            .{ .x = x + @cos(angle1) * radius, .y = y, .z = z + @sin(angle1) * radius },
            .{ .x = x + @cos(angle2) * radius, .y = y, .z = z + @sin(angle2) * radius },
            color,
        );
    }
}

/// Draw an arced wall preview (curves toward caster)
fn drawArcWallPreview(
    center_x: f32,
    center_y: f32,
    center_z: f32,
    facing_angle: f32,
    length: f32,
    height: f32,
    thickness: f32,
    arc_factor: f32,
    fill_color: rl.Color,
    outline_color: rl.Color,
) void {
    // Wall is perpendicular to facing angle, with arc curving toward caster
    const perp_angle = facing_angle + std.math.pi / 2.0;
    const half_length = length / 2.0;
    const half_thickness = thickness / 2.0;
    const arc_depth = length * arc_factor; // How far the arc curves back

    // Number of segments for the arc (more = smoother)
    const segments: u32 = 12;
    const seg_f = @as(f32, @floatFromInt(segments));

    // Calculate corner positions
    const cos_perp = @cos(perp_angle);
    const sin_perp = @sin(perp_angle);
    const cos_face = @cos(facing_angle);
    const sin_face = @sin(facing_angle);

    // Generate arc points along the wall
    // Arc formula: offset toward caster based on distance from center
    // Using parabola: arc_offset = arc_depth * (1 - (t/half_length)^2) where t is distance from center
    var front_points: [13]rl.Vector3 = undefined;
    var back_points: [13]rl.Vector3 = undefined;

    var i: u32 = 0;
    while (i <= segments) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / seg_f; // 0 to 1
        const wall_pos = (t - 0.5) * 2.0; // -1 to 1 (left to right)
        const lateral_offset = wall_pos * half_length;

        // Parabolic arc: maximum curve at center (wall_pos = 0), zero at edges (wall_pos = ±1)
        const arc_offset = arc_depth * (1.0 - wall_pos * wall_pos);

        // Position along the wall (perpendicular direction)
        const base_x = center_x + cos_perp * lateral_offset;
        const base_z = center_z + sin_perp * lateral_offset;

        // Front edge (away from caster)
        front_points[i] = .{
            .x = base_x - cos_face * half_thickness,
            .y = center_y,
            .z = base_z - sin_face * half_thickness,
        };

        // Back edge (toward caster, with arc offset)
        back_points[i] = .{
            .x = base_x + cos_face * (half_thickness + arc_offset),
            .y = center_y,
            .z = base_z + sin_face * (half_thickness + arc_offset),
        };
    }

    // Draw filled wall segments (triangles)
    i = 0;
    while (i < segments) : (i += 1) {
        // Bottom face (two triangles per segment)
        rl.drawTriangle3D(front_points[i], front_points[i + 1], back_points[i + 1], fill_color);
        rl.drawTriangle3D(front_points[i], back_points[i + 1], back_points[i], fill_color);

        // Top face
        const top_front_1 = rl.Vector3{ .x = front_points[i].x, .y = center_y + height, .z = front_points[i].z };
        const top_front_2 = rl.Vector3{ .x = front_points[i + 1].x, .y = center_y + height, .z = front_points[i + 1].z };
        const top_back_1 = rl.Vector3{ .x = back_points[i].x, .y = center_y + height, .z = back_points[i].z };
        const top_back_2 = rl.Vector3{ .x = back_points[i + 1].x, .y = center_y + height, .z = back_points[i + 1].z };

        rl.drawTriangle3D(top_front_1, top_back_1, top_back_2, fill_color);
        rl.drawTriangle3D(top_front_1, top_back_2, top_front_2, fill_color);
    }

    // Draw outline edges
    // Front edge (arc)
    i = 0;
    while (i < segments) : (i += 1) {
        rl.drawLine3D(front_points[i], front_points[i + 1], outline_color);
        // Top front edge
        const top_1 = rl.Vector3{ .x = front_points[i].x, .y = center_y + height, .z = front_points[i].z };
        const top_2 = rl.Vector3{ .x = front_points[i + 1].x, .y = center_y + height, .z = front_points[i + 1].z };
        rl.drawLine3D(top_1, top_2, outline_color);
    }

    // Back edge (arc)
    i = 0;
    while (i < segments) : (i += 1) {
        rl.drawLine3D(back_points[i], back_points[i + 1], outline_color);
        // Top back edge
        const top_1 = rl.Vector3{ .x = back_points[i].x, .y = center_y + height, .z = back_points[i].z };
        const top_2 = rl.Vector3{ .x = back_points[i + 1].x, .y = center_y + height, .z = back_points[i + 1].z };
        rl.drawLine3D(top_1, top_2, outline_color);
    }

    // Vertical edges at ends
    const top_front_left = rl.Vector3{ .x = front_points[0].x, .y = center_y + height, .z = front_points[0].z };
    const top_front_right = rl.Vector3{ .x = front_points[segments].x, .y = center_y + height, .z = front_points[segments].z };
    const top_back_left = rl.Vector3{ .x = back_points[0].x, .y = center_y + height, .z = back_points[0].z };
    const top_back_right = rl.Vector3{ .x = back_points[segments].x, .y = center_y + height, .z = back_points[segments].z };

    rl.drawLine3D(front_points[0], top_front_left, outline_color);
    rl.drawLine3D(front_points[segments], top_front_right, outline_color);
    rl.drawLine3D(back_points[0], top_back_left, outline_color);
    rl.drawLine3D(back_points[segments], top_back_right, outline_color);

    // End caps
    rl.drawLine3D(front_points[0], back_points[0], outline_color);
    rl.drawLine3D(front_points[segments], back_points[segments], outline_color);
    rl.drawLine3D(top_front_left, top_back_left, outline_color);
    rl.drawLine3D(top_front_right, top_back_right, outline_color);
}

/// Draw a wall preview (rectangle perpendicular to facing) - legacy, non-arced
fn drawWallPreview(
    center_x: f32,
    center_y: f32,
    center_z: f32,
    facing_angle: f32,
    length: f32,
    height: f32,
    thickness: f32,
    fill_color: rl.Color,
    outline_color: rl.Color,
) void {
    // Wall is perpendicular to facing angle
    const perp_angle = facing_angle + std.math.pi / 2.0;
    const half_length = length / 2.0;
    const half_thickness = thickness / 2.0;

    // Calculate corner positions
    const cos_perp = @cos(perp_angle);
    const sin_perp = @sin(perp_angle);
    const cos_face = @cos(facing_angle);
    const sin_face = @sin(facing_angle);

    // Base corners (on ground)
    const corners = [4]rl.Vector3{
        .{
            .x = center_x - cos_perp * half_length - cos_face * half_thickness,
            .y = center_y,
            .z = center_z - sin_perp * half_length - sin_face * half_thickness,
        },
        .{
            .x = center_x + cos_perp * half_length - cos_face * half_thickness,
            .y = center_y,
            .z = center_z + sin_perp * half_length - sin_face * half_thickness,
        },
        .{
            .x = center_x + cos_perp * half_length + cos_face * half_thickness,
            .y = center_y,
            .z = center_z + sin_perp * half_length + sin_face * half_thickness,
        },
        .{
            .x = center_x - cos_perp * half_length + cos_face * half_thickness,
            .y = center_y,
            .z = center_z - sin_perp * half_length + sin_face * half_thickness,
        },
    };

    // Draw base rectangle
    rl.drawTriangle3D(corners[0], corners[1], corners[2], fill_color);
    rl.drawTriangle3D(corners[0], corners[2], corners[3], fill_color);

    // Draw top rectangle
    const top_corners = [4]rl.Vector3{
        .{ .x = corners[0].x, .y = center_y + height, .z = corners[0].z },
        .{ .x = corners[1].x, .y = center_y + height, .z = corners[1].z },
        .{ .x = corners[2].x, .y = center_y + height, .z = corners[2].z },
        .{ .x = corners[3].x, .y = center_y + height, .z = corners[3].z },
    };

    rl.drawTriangle3D(top_corners[0], top_corners[2], top_corners[1], fill_color);
    rl.drawTriangle3D(top_corners[0], top_corners[3], top_corners[2], fill_color);

    // Draw vertical edges
    rl.drawLine3D(corners[0], top_corners[0], outline_color);
    rl.drawLine3D(corners[1], top_corners[1], outline_color);
    rl.drawLine3D(corners[2], top_corners[2], outline_color);
    rl.drawLine3D(corners[3], top_corners[3], outline_color);

    // Draw base outline
    rl.drawLine3D(corners[0], corners[1], outline_color);
    rl.drawLine3D(corners[1], corners[2], outline_color);
    rl.drawLine3D(corners[2], corners[3], outline_color);
    rl.drawLine3D(corners[3], corners[0], outline_color);

    // Draw top outline
    rl.drawLine3D(top_corners[0], top_corners[1], outline_color);
    rl.drawLine3D(top_corners[1], top_corners[2], outline_color);
    rl.drawLine3D(top_corners[2], top_corners[3], outline_color);
    rl.drawLine3D(top_corners[3], top_corners[0], outline_color);
}

/// Draw a cone preview
fn drawConePreview(
    origin_x: f32,
    y: f32,
    origin_z: f32,
    facing_angle: f32,
    length: f32,
    cone_angle: f32,
    fill_color: rl.Color,
    outline_color: rl.Color,
) void {
    const segments: u32 = 12;
    const half_angle = cone_angle / 2.0;
    const angle_step = cone_angle / @as(f32, @floatFromInt(segments));

    // Draw cone triangles
    var i: u32 = 0;
    while (i < segments) : (i += 1) {
        const angle1 = facing_angle - half_angle + @as(f32, @floatFromInt(i)) * angle_step;
        const angle2 = facing_angle - half_angle + @as(f32, @floatFromInt(i + 1)) * angle_step;

        rl.drawTriangle3D(
            .{ .x = origin_x, .y = y, .z = origin_z },
            .{ .x = origin_x + @cos(angle1) * length, .y = y, .z = origin_z + @sin(angle1) * length },
            .{ .x = origin_x + @cos(angle2) * length, .y = y, .z = origin_z + @sin(angle2) * length },
            fill_color,
        );
    }

    // Draw outline
    const left_edge_x = origin_x + @cos(facing_angle - half_angle) * length;
    const left_edge_z = origin_z + @sin(facing_angle - half_angle) * length;
    const right_edge_x = origin_x + @cos(facing_angle + half_angle) * length;
    const right_edge_z = origin_z + @sin(facing_angle + half_angle) * length;

    rl.drawLine3D(
        .{ .x = origin_x, .y = y, .z = origin_z },
        .{ .x = left_edge_x, .y = y, .z = left_edge_z },
        outline_color,
    );
    rl.drawLine3D(
        .{ .x = origin_x, .y = y, .z = origin_z },
        .{ .x = right_edge_x, .y = y, .z = right_edge_z },
        outline_color,
    );

    // Draw arc at end of cone
    i = 0;
    while (i < segments) : (i += 1) {
        const angle1 = facing_angle - half_angle + @as(f32, @floatFromInt(i)) * angle_step;
        const angle2 = facing_angle - half_angle + @as(f32, @floatFromInt(i + 1)) * angle_step;

        rl.drawLine3D(
            .{ .x = origin_x + @cos(angle1) * length, .y = y, .z = origin_z + @sin(angle1) * length },
            .{ .x = origin_x + @cos(angle2) * length, .y = y, .z = origin_z + @sin(angle2) * length },
            outline_color,
        );
    }
}
