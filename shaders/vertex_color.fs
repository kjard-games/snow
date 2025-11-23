#version 330

// Input from vertex shader
in vec3 fragPosition;
in vec3 fragNormal;
in vec4 fragColor;

// Output fragment color
out vec4 finalColor;

// Simple directional light (sun)
const vec3 lightDir = normalize(vec3(-0.3, -1.0, -0.4)); // Light coming from top-left
const vec3 lightColor = vec3(1.0, 0.98, 0.95); // Slightly warm sunlight
const float ambientStrength = 0.6; // Base ambient light (winter sky is bright)
const float diffuseStrength = 0.5; // Diffuse light strength

// Procedural detail noise (GoW-inspired approach)
// Simple hash function for pseudo-random values
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Multi-octave noise for natural detail
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f); // Smoothstep interpolation
    
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Fractal Brownian Motion for natural snow texture
float fbm(vec2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    
    // 3 octaves for detail without too much performance cost
    for (int i = 0; i < 3; i++) {
        value += amplitude * noise(p * frequency);
        frequency *= 2.0;
        amplitude *= 0.5;
    }
    
    return value;
}

// Generate detail normal from procedural noise
vec3 calculateDetailNormal(vec3 worldPos, vec3 baseNormal) {
    // High frequency detail for snow surface texture
    float scale = 8.0; // Controls detail size
    vec2 uv = worldPos.xz * scale;
    
    // Sample noise at slightly offset positions to calculate gradient
    float epsilon = 0.1;
    float heightCenter = fbm(uv);
    float heightRight = fbm(uv + vec2(epsilon, 0.0));
    float heightUp = fbm(uv + vec2(0.0, epsilon));
    
    // Calculate gradient (derivative) for normal perturbation
    vec2 gradient = vec2(heightRight - heightCenter, heightUp - heightCenter) / epsilon;
    
    // Small strength factor (too strong looks unnatural)
    float detailStrength = 0.15;
    
    // Perturb the base normal with the gradient
    vec3 detailNormal = normalize(vec3(
        gradient.x * detailStrength,
        1.0,
        gradient.y * detailStrength
    ));
    
    // Blend detail normal with base normal
    // This is a simplified version of what GoW does with detail normal maps
    return normalize(baseNormal + detailNormal * 0.3);
}

void main()
{
    // Start with base normal
    vec3 normal = normalize(fragNormal);
    
    // Add procedural detail to the normal (GoW-style detail normal mapping)
    // Only add detail to near-horizontal surfaces (snow top surface)
    float horizontalness = max(0.0, normal.y); // 1.0 = flat horizontal, 0.0 = vertical
    if (horizontalness > 0.3) {
        vec3 detailNormal = calculateDetailNormal(fragPosition, normal);
        // Blend based on how horizontal the surface is
        normal = mix(normal, detailNormal, horizontalness * horizontalness);
    }
    
    // Calculate diffuse lighting (Lambertian)
    float diff = max(dot(normal, -lightDir), 0.0);
    
    // Combine ambient + diffuse
    vec3 ambient = ambientStrength * lightColor;
    vec3 diffuse = diffuseStrength * diff * lightColor;
    vec3 lighting = ambient + diffuse;
    
    // Add subtle color variation to snow (GoW-style detail texture)
    // High-frequency noise for fine grain
    float colorNoise = fbm(fragPosition.xz * 16.0);
    float colorVariation = 0.97 + colorNoise * 0.06; // Very subtle: 0.97 to 1.03
    
    // Apply lighting and color variation to vertex color
    vec3 litColor = fragColor.rgb * lighting * colorVariation;
    
    // Output final color
    finalColor = vec4(litColor, fragColor.a);
}