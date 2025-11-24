#version 330

// Input vertex attributes (location MUST match raylib's vertex attribute locations)
// Raylib attribute locations: 0=position, 1=texcoord, 2=normal, 3=color, 4=tangent
layout (location = 0) in vec3 vertexPosition;
layout (location = 2) in vec3 vertexNormal;
layout (location = 3) in vec4 vertexColor;

// Input uniform values (automatically set by raylib)
uniform mat4 mvp;
uniform mat4 matModel;
uniform mat4 matNormal;

// Output vertex attributes (to fragment shader)
out vec3 fragPosition;
out vec3 fragWorldPosition;  // World space position for layer detection
out vec3 fragNormal;
out vec4 fragColor;

void main()
{
    // Calculate final vertex position
    gl_Position = mvp * vec4(vertexPosition, 1.0);
    
    // Send world position and normal to fragment shader for lighting
    fragPosition = vec3(matModel * vec4(vertexPosition, 1.0));
    fragWorldPosition = vertexPosition;  // Raw world position for height-based effects
    fragNormal = normalize(vec3(matNormal * vec4(vertexNormal, 0.0)));
    
    // Pass vertex color to fragment shader
    fragColor = vertexColor;
}