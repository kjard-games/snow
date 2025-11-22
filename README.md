# Snow - Game Prototype

A 3D/isometric game prototype built with RayLib and Zig.

## Setup

### Prerequisites
- Zig 0.15.2 or later
- Git

### Installation

1. Clone this repository:
```bash
git clone <repository-url>
cd snow
```

2. Build and run the game:
```bash
zig build run
```

## Development

### Building
```bash
zig build
```

### Running
```bash
zig build run
```

### Project Structure
- `src/main.zig` - Main game entry point
- `build.zig` - Build configuration
- `build.zig.zon` - Zig package dependencies

## Dependencies

- [RayLib](https://github.com/raysan5/raylib) - Simple and easy-to-use library to enjoy videogames programming
- [raylib-zig](https://github.com/raylib-zig/raylib-zig) - Zig bindings for RayLib

## Game Controls

### Keyboard Controls

#### Movement
- **WASD** - Move forward/left/backward/right (relative to camera)
- **R** - Toggle autorun
- **X** - Quick 180° turn
- **Left Click (terrain)** - Click-to-move
- **ESC** - Cancel casting

#### Camera
- **Right Mouse Button (hold)** - Mouse-look camera control
- **C** - Toggle Action Camera mode (always mouse-look)
- **Mouse Wheel** - Zoom in/out

#### Targeting
- **Tab** - Cycle through enemies (forward)
- **Shift+Tab** - Cycle through enemies (backward)
- **Ctrl+Tab** - Cycle through allies (forward)
- **Ctrl+Shift+Tab** - Cycle through allies (backward)
- **T** - Target nearest enemy
- **Y** - Target nearest ally
- **H** - Target lowest health ally (for healing)
- **F1** - Target self
- **Left Click (entity)** - Target entity
- **Double-click (entity)** - Target and move to entity

#### Skills & Combat
- **1-8** - Use skills 1-8
- **Space** - Toggle auto-attack
- **Q/E** - Cycle selected skill (for UI highlighting)
- **[ ]** - Cycle through skill tooltips (inspection mode)

### Controller (Gamepad) Controls

#### Movement
- **Left Stick** - Move character (relative to camera)
- **Right Stick** - Control camera (yaw and pitch)
- **L3 (Left Stick Click)** - Toggle Action Camera mode

#### Targeting
- **R2** - Cycle through enemies (forward)
- **L2** - Cycle through enemies (backward)
- **L1+R2** - Cycle through allies (forward)
- **L1+L2** - Cycle through allies (backward)
- **D-pad Up** - Target self
- **D-pad Right** - Cycle allies forward
- **D-pad Left** - Cycle allies backward
- **R1+D-Right** - Target nearest enemy
- **R1+D-Left** - Target nearest ally
- **R1+D-Down** - Target lowest health ally

#### Skills & Combat
- **A (Right Face Down)** - Use skill 1 / Cancel casting
- **B (Right Face Right)** - Use skill 2
- **X (Right Face Left)** - Use skill 3
- **Y (Right Face Up)** - Use skill 4
- **L1+A** - Use skill 5
- **L1+B** - Use skill 6
- **L1+X** - Use skill 7
- **L1+Y** - Use skill 8
- **R1** - Toggle auto-attack

#### UI & Inspection
- **D-pad Down** - Toggle skill tooltip inspection mode
- **Right Stick Left/Right** - Navigate skill tooltips (when in inspection mode)

### Gameplay Tips
- Movement cancels casting (GW1 style)
- Skills can be queued when out of range - you'll automatically approach and cast
- Auto-attack makes you chase your target when out of range
- Terrain affects movement speed (deep snow slows you down)
- Walking through snow packs it down, creating faster paths over time

## License

MIT License