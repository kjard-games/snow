#version 330

// Input from vertex shader
in vec2 fragTexCoord;
in vec4 fragColor;

// Output
out vec4 finalColor;

// Uniforms
uniform sampler2D texture0;      // Scene color texture
uniform vec2 resolution;          // Screen resolution
uniform float outlineThickness;   // Thickness of outline in pixels

// Sobel edge detection kernel
const float sobelX[9] = float[](
    -1.0, 0.0, 1.0,
    -2.0, 0.0, 2.0,
    -1.0, 0.0, 1.0
);

const float sobelY[9] = float[](
    -1.0, -2.0, -1.0,
     0.0,  0.0,  0.0,
     1.0,  2.0,  1.0
);

void main()
{
    vec2 texelSize = outlineThickness / resolution;
    
    // Sample the scene color
    vec4 sceneColor = texture(texture0, fragTexCoord);
    
    // If pixel is transparent (background), no outline
    if (sceneColor.a < 0.01) {
        finalColor = sceneColor;
        return;
    }
    
    // Sobel edge detection on alpha channel
    float edgeX = 0.0;
    float edgeY = 0.0;
    
    int index = 0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 offset = vec2(float(x), float(y)) * texelSize;
            float alpha = texture(texture0, fragTexCoord + offset).a;
            
            edgeX += alpha * sobelX[index];
            edgeY += alpha * sobelY[index];
            index++;
        }
    }
    
    // Calculate edge strength
    float edge = sqrt(edgeX * edgeX + edgeY * edgeY);
    
    // If we're on an edge, blend with the outline color (stored in RGB of scene)
    if (edge > 0.3) {
        // The outline color is stored in the RGB channels where alpha > 0.5
        if (sceneColor.a > 0.5) {
            finalColor = vec4(sceneColor.rgb, 1.0);
        } else {
            finalColor = vec4(sceneColor.rgb, edge);
        }
    } else {
        // Not an edge, make it transparent
        finalColor = vec4(0.0, 0.0, 0.0, 0.0);
    }
}
