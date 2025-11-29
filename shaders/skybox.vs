#version 330

// Input vertex attributes
layout (location = 0) in vec3 vertexPosition;

// Input uniform values
uniform mat4 mvp;

// Output to fragment shader - use position as direction for cubemap lookup
out vec3 fragTexCoord;

void main()
{
    // Use vertex position as the direction vector for cubemap sampling
    fragTexCoord = vertexPosition;
    
    // Calculate position, keeping z = w so depth is always at far plane
    vec4 pos = mvp * vec4(vertexPosition, 1.0);
    gl_Position = pos.xyww;
}
