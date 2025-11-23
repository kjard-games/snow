#version 330

// Input from vertex shader
in vec3 fragPosition;
in vec3 fragNormal;
in vec4 fragColor;

// Output fragment color
out vec4 finalColor;

// Directional light (sun) - God of War style winter sun
// GoW keeps it SIMPLE: bright vertex colors + good lighting = beautiful snow
const vec3 lightDir = normalize(vec3(-0.3, -1.0, -0.4)); // Light from above-left
const vec3 lightColor = vec3(1.0, 0.98, 0.95); // Bright warm sunlight
const float ambientStrength = 0.70; // High ambient - snow reflects skylight everywhere
const float diffuseStrength = 0.35; // Moderate directional component

void main()
{
    // Normalize the normal
    vec3 normal = normalize(fragNormal);
    
    // === SIMPLE DIFFUSE LIGHTING (GoW-style) ===
    // Calculate how much this surface faces the light
    float NdotL = max(dot(normal, -lightDir), 0.0);
    
    // Very slight wrap for soft shadows (snow scatters light)
    float wrap = 0.15;
    float diffuse = (NdotL + wrap) / (1.0 + wrap);
    diffuse = max(0.0, diffuse);
    
    // === COMBINE LIGHTING ===
    vec3 ambient = ambientStrength * lightColor;
    vec3 diffuseLight = diffuseStrength * diffuse * lightColor;
    vec3 totalLight = ambient + diffuseLight;
    
    // === APPLY TO VERTEX COLOR ===
    // GoW key: vertex color is already bright (250-255), just multiply by light
    vec3 litColor = fragColor.rgb * totalLight;
    
    // Clamp to prevent oversaturation but keep it BRIGHT
    litColor = min(litColor, vec3(1.0));
    
    // Output final color - NO tone mapping, NO desaturation, keep it BRIGHT!
    finalColor = vec4(litColor, fragColor.a);
}
