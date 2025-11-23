#version 330

// Input vertex attributes (location MUST match raylib's vertex attribute locations)
// Raylib attribute locations: 0=position, 1=texcoord, 2=normal, 3=color, 4=tangent
layout (location = 0) in vec3 vertexPosition;
layout (location = 3) in vec4 vertexColor;

// Input uniform values (automatically set by raylib)
uniform mat4 mvp;

// Output vertex attributes (to fragment shader)
out vec4 fragColor;

void main()
{
    // Calculate final vertex position
    gl_Position = mvp * vec4(vertexPosition, 1.0);
    
    // Pass vertex color to fragment shader
    // DEBUG: Force a test color to verify shader is working
    // fragColor = vec4(1.0, 0.0, 0.0, 1.0); // RED test
    fragColor = vertexColor;
}