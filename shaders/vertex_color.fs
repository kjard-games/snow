#version 330

// Input from vertex shader
in vec3 fragPosition;
in vec3 fragNormal;
in vec4 fragColor;

// Output fragment color
out vec4 finalColor;

// Time-of-day lighting uniforms (set by CPU)
uniform vec3 sunDirection;      // Direction TO the sun (for day/evening)
uniform vec3 sunColor;          // Sun/sky color (changes with time of day)
uniform float ambientStrength;  // How much ambient light
uniform float diffuseStrength;  // How much directional light
uniform vec3 ambientColor;      // Ambient light color (sky color)

// Subsurface scattering parameters
const float sssStrength = 0.4;  // How much light penetrates snow
const vec3 sssColor = vec3(0.9, 0.85, 0.75); // Warm glow inside snow

void main()
{
    // Normalize the normal
    vec3 normal = normalize(fragNormal);
    
    // Calculate view direction (needed for SSS)
    vec3 viewDir = normalize(-fragPosition);
    
    // === DIFFUSE LIGHTING (GoW-style) ===
    // Calculate how much this surface faces the light
    float NdotL = max(dot(normal, -sunDirection), 0.0);
    
    // Wrap lighting for soft shadows (snow scatters light)
    float wrap = 0.2;
    float diffuse = (NdotL + wrap) / (1.0 + wrap);
    diffuse = max(0.0, diffuse);
    
    // === SUBSURFACE SCATTERING ===
    // Snow is translucent - light penetrates and scatters inside
    // This creates the soft glow you see in real snow
    
    // Back-lighting: light coming through the snow from behind
    float backLight = max(0.0, dot(-normal, -sunDirection));
    
    // View-dependent rim glow (snow glows at edges when backlit)
    float rimFactor = 1.0 - max(0.0, dot(normal, viewDir));
    rimFactor = pow(rimFactor, 3.0); // Tighter rim
    
    // Combine for subsurface effect
    float sss = (backLight * 0.5 + rimFactor * 0.5) * sssStrength;
    
    // Only apply SSS to bright snow (not dark ground)
    float snowiness = (fragColor.r + fragColor.g + fragColor.b) / 3.0;
    sss *= smoothstep(0.5, 0.9, snowiness);
    
    // === COMBINE LIGHTING ===
    vec3 ambient = ambientStrength * ambientColor;
    vec3 diffuseLight = diffuseStrength * diffuse * sunColor;
    vec3 sssLight = sss * sunColor * sssColor;
    
    vec3 totalLight = ambient + diffuseLight + sssLight;
    
    // === APPLY TO VERTEX COLOR ===
    vec3 litColor = fragColor.rgb * totalLight;
    
    // Clamp to prevent oversaturation but keep it BRIGHT
    litColor = min(litColor, vec3(1.2)); // Allow slight overbright for SSS glow
    
    // Output final color
    finalColor = vec4(litColor, fragColor.a);
}
