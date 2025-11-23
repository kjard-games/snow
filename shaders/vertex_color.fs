#version 330

// Input from vertex shader
in vec3 fragPosition;
in vec3 fragNormal;
in vec4 fragColor;

// Output fragment color
out vec4 finalColor;

// Directional light (sun) - God of War style winter sun
// Key insight: BRIGHT snow + MODERATE lighting = realistic look (not dark snow + bright lighting)
const vec3 lightDir = normalize(vec3(-0.3, -1.0, -0.4)); // Light coming from top-left-back
const vec3 lightColor = vec3(1.0, 0.98, 0.95); // Bright neutral sunlight (slightly warm)
const float ambientStrength = 0.65; // Strong ambient for snow (reflects skylight)
const float diffuseStrength = 0.50; // Moderate directional lighting

// === PROCEDURAL NOISE (GoW-inspired) ===

// High-quality hash for better pseudo-random distribution
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float hash3(vec3 p) {
    return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

// Improved noise with smoother interpolation
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f); // Smoothstep
    
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Multi-scale Fractal Brownian Motion (multiple octaves for natural detail)
float fbm(vec2 p, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    
    for (int i = 0; i < octaves; i++) {
        value += amplitude * noise(p * frequency);
        frequency *= 2.0;
        amplitude *= 0.5;
    }
    
    return value;
}

// === MULTI-SCALE DETAIL NORMAL MAPPING (GoW Approach) ===

// Calculate detail normal from procedural noise at multiple scales
// GoW uses detail normal maps at different frequencies - we simulate this procedurally
vec3 calculateDetailNormal(vec3 worldPos, vec3 baseNormal) {
    vec3 perturbation = vec3(0.0);
    
    // Large-scale detail (broad drifts and formations) - VERY SUBTLE
    float scale1 = 2.0;
    vec2 uv1 = worldPos.xz * scale1;
    float epsilon1 = 0.15;
    float h1c = fbm(uv1, 2);
    float h1r = fbm(uv1 + vec2(epsilon1, 0.0), 2);
    float h1u = fbm(uv1 + vec2(0.0, epsilon1), 2);
    vec2 grad1 = vec2(h1r - h1c, h1u - h1c) / epsilon1;
    perturbation += vec3(grad1.x, 0.0, grad1.y) * 0.12; // Much more subtle
    
    // Medium-scale detail (smaller ripples and texture) - VERY SUBTLE
    float scale2 = 8.0;
    vec2 uv2 = worldPos.xz * scale2;
    float epsilon2 = 0.08;
    float h2c = fbm(uv2, 3);
    float h2r = fbm(uv2 + vec2(epsilon2, 0.0), 3);
    float h2u = fbm(uv2 + vec2(0.0, epsilon2), 3);
    vec2 grad2 = vec2(h2r - h2c, h2u - h2c) / epsilon2;
    perturbation += vec3(grad2.x, 0.0, grad2.y) * 0.08; // Much more subtle
    
    // Fine-scale detail (micro-surface texture) - VERY SUBTLE
    float scale3 = 24.0;
    vec2 uv3 = worldPos.xz * scale3;
    float epsilon3 = 0.04;
    float h3c = fbm(uv3, 2);
    float h3r = fbm(uv3 + vec2(epsilon3, 0.0), 2);
    float h3u = fbm(uv3 + vec2(0.0, epsilon3), 2);
    vec2 grad3 = vec2(h3r - h3c, h3u - h3c) / epsilon3;
    perturbation += vec3(grad3.x, 0.0, grad3.y) * 0.04; // Much more subtle
    
    // Blend with base normal - MINIMAL strength (detail is subtle)
    return normalize(baseNormal + perturbation * 0.25);
}

// === SUBSURFACE SCATTERING APPROXIMATION (GoW-style) ===

// Cheap approximation of snow's translucency - TONED DOWN
// Snow scatters light that enters it, creating a soft glow
float calculateSubsurfaceScattering(vec3 normal, vec3 lightDir, vec3 viewDir) {
    // Light penetrates surface and scatters inside snow
    // Approximate with wrap-around lighting
    float backlight = max(0.0, dot(-normal, lightDir));
    
    // Add view-dependent rim effect (snow glows at grazing angles) - REDUCED
    float rim = 1.0 - max(0.0, dot(normal, viewDir));
    rim = pow(rim, 4.0); // Increased power for tighter rim (was 3.0)
    
    // Combine backlight and rim for subsurface effect - REDUCED
    return backlight * 0.2 + rim * 0.15; // Reduced from 0.4 and 0.3
}

// === SPARKLE/GLITTER EFFECT (GoW-style) ===

// Snow crystals catch light and sparkle - MUCH REDUCED
// Use high-frequency noise with view-dependent falloff
float calculateSparkle(vec3 worldPos, vec3 normal, vec3 viewDir) {
    // High-frequency sparkle pattern (individual crystals)
    vec3 sparkleCoord = worldPos * 80.0;
    float sparkleNoise = hash3(floor(sparkleCoord));
    
    // Only sparkle where view is near specular reflection angle
    vec3 halfDir = normalize(-lightDir + viewDir);
    float specAngle = max(0.0, dot(normal, halfDir));
    float sparkleCondition = pow(specAngle, 256.0); // Much tighter (was 128.0)
    
    // Random intensity per crystal - MUCH LESS FREQUENT
    float sparkleIntensity = step(0.97, sparkleNoise); // Only 3% sparkle (was 8%)
    
    return sparkleIntensity * sparkleCondition * 0.3; // Much weaker (was 0.8)
}

// === HEIGHT-BASED COLOR VARIATION (GoW Approach) ===

// Snow in valleys is shadowed, peaks are bright
// Displaced snow (footprints) shows underlying layers
vec3 applyHeightBasedColor(vec3 baseColor, float worldHeight, float verticalness) {
    // MINIMAL color shift - GoW keeps snow bright across all heights
    // Only very subtle ambient occlusion in deep valleys
    float heightFactor = smoothstep(-50.0, 100.0, worldHeight);
    float heightTint = 0.92 + heightFactor * 0.08; // Very minimal darkening
    
    // Vertical surfaces only slightly darker
    float sideDarkening = mix(0.95, 1.0, verticalness); // Minimal darkening
    
    // Very subtle blue tint to shadows (sky light reflection)
    vec3 shadowTint = vec3(0.97, 0.98, 1.0); // Very subtle
    vec3 colorWithHeight = baseColor * heightTint * sideDarkening;
    
    // Minimal shadow tint blending
    return mix(colorWithHeight * shadowTint, colorWithHeight, 0.5 + heightFactor * 0.5);
}

// === TONE MAPPING ===
// Prevents blown-out highlights while preserving detail
vec3 reinhardToneMapping(vec3 color) {
    // Simple Reinhard tone mapping
    return color / (vec3(1.0) + color);
}

vec3 filmicToneMapping(vec3 color) {
    // ACES-like filmic tone mapping (simplified)
    vec3 x = max(vec3(0.0), color - 0.004);
    return (x * (6.2 * x + 0.5)) / (x * (6.2 * x + 1.7) + 0.06);
}

void main()
{
    // Start with base normal
    vec3 normal = normalize(fragNormal);
    
    // Calculate view direction (camera to fragment)
    vec3 viewDir = normalize(-fragPosition); // Assume camera at origin in view space
    
    // Calculate how horizontal vs vertical this surface is
    float horizontalness = abs(normal.y); // 1.0 = horizontal, 0.0 = vertical
    float verticalness = 1.0 - horizontalness;
    
    // === DETAIL NORMAL MAPPING (Multi-scale, GoW-style) ===
    // Only apply to top surfaces (snow detail), not steep slopes
    if (horizontalness > 0.4) {
        vec3 detailedNormal = calculateDetailNormal(fragPosition, normal);
        // Blend based on how horizontal the surface is
        float detailBlend = smoothstep(0.4, 0.9, horizontalness);
        normal = normalize(mix(normal, detailedNormal, detailBlend));
    }
    
    // === DIFFUSE LIGHTING ===
    // GoW uses relatively crisp lighting with strong ambient
    float NdotL = max(dot(normal, -lightDir), 0.0);
    
    // Minimal wrap lighting - strong ambient handles soft shadows
    float wrap = 0.2; // Minimal wrap for crisp lighting
    float diffuse = (NdotL + wrap) / (1.0 + wrap);
    diffuse = max(0.0, diffuse);
    
    // === SUBSURFACE SCATTERING ===
    // Snow is translucent - light penetrates and scatters
    float sss = calculateSubsurfaceScattering(normal, lightDir, viewDir);
    
    // === SPARKLE EFFECT ===
    // Snow crystals catch light and glitter
    float sparkle = calculateSparkle(fragPosition, normal, viewDir);
    
    // === HEIGHT-BASED COLOR VARIATION ===
    vec3 snowColor = applyHeightBasedColor(fragColor.rgb, fragPosition.y, verticalness);
    
    // === MULTI-FREQUENCY COLOR DETAIL (GoW approach) ===
    // Add VERY subtle color variation - keep snow bright!
    float colorDetail1 = fbm(fragPosition.xz * 3.0, 2) * 0.01; // Very minimal
    float colorDetail2 = fbm(fragPosition.xz * 12.0, 3) * 0.008; // Very minimal
    float colorDetail3 = fbm(fragPosition.xz * 32.0, 2) * 0.005; // Very minimal
    float totalColorVariation = 1.0 + colorDetail1 + colorDetail2 + colorDetail3;
    
    // === COMBINE LIGHTING ===
    vec3 ambient = ambientStrength * lightColor;
    vec3 diffuseLight = diffuseStrength * diffuse * lightColor;
    
    // Add subsurface scattering (warm glow in shadows) - REDUCED
    vec3 sssLight = sss * lightColor * vec3(0.9, 0.85, 0.75); // Less intense, more subtle
    
    // Add sparkle (bright white highlights) - MUCH REDUCED
    vec3 sparkleLight = sparkle * vec3(0.6, 0.55, 0.5); // Much weaker (was 1.5, 1.4, 1.3)
    
    // Combine all lighting
    vec3 totalLight = ambient + diffuseLight + sssLight;
    
    // === FINAL COLOR COMPOSITION ===
    vec3 litColor = snowColor * totalLight * totalColorVariation;
    
    // Add sparkles on top (additive)
    litColor += sparkleLight;
    
    // === TONE MAPPING (prevent blown-out highlights) ===
    // GoW keeps snow BRIGHT - minimal tone mapping to preserve white
    litColor = reinhardToneMapping(litColor * 1.0); // Don't scale down - keep bright!
    
    // Very subtle desaturation only in deepest shadows
    float luminance = dot(litColor, vec3(0.299, 0.587, 0.114));
    float desatFactor = smoothstep(0.2, 0.6, luminance);
    litColor = mix(vec3(luminance), litColor, 0.85 + desatFactor * 0.15); // Minimal desaturation
    
    // Output final color
    finalColor = vec4(litColor, fragColor.a);
}
