#version 330

// Fragment shader for team outlines
in vec2 fragTexCoord;

out vec4 finalColor;

uniform sampler2D texture0;     // Main scene texture
uniform vec2 resolution;        // Screen resolution
uniform float thickness;        // Outline thickness

void main()
{
    vec2 texelSize = 1.0 / resolution * thickness;
    
    // Sample center pixel
    vec4 center = texture(texture0, fragTexCoord);
    
    // If center is transparent (background), output transparent
    if (center.a < 0.01) {
        finalColor = vec4(0.0);
        return;
    }
    
    // Sample surrounding pixels in a cross pattern
    vec4 up = texture(texture0, fragTexCoord + vec2(0.0, texelSize.y));
    vec4 down = texture(texture0, fragTexCoord + vec2(0.0, -texelSize.y));
    vec4 left = texture(texture0, fragTexCoord + vec2(-texelSize.x, 0.0));
    vec4 right = texture(texture0, fragTexCoord + vec2(texelSize.x, 0.0));
    
    // Check if any neighbor is transparent (edge detection)
    float edge = 0.0;
    if (up.a < 0.5) edge = 1.0;
    else if (down.a < 0.5) edge = 1.0;
    else if (left.a < 0.5) edge = 1.0;
    else if (right.a < 0.5) edge = 1.0;
    
    // If we're on an edge, draw the team color outline
    if (edge > 0.0) {
        finalColor = vec4(center.rgb, 1.0);
    } else {
        // Not an edge, pass through transparent
        finalColor = vec4(0.0);
    }
}
