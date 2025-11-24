#version 330

// Input from vertex shader
in vec3 fragPosition;
in vec3 fragWorldPosition;
in vec3 fragNormal;
in vec4 fragColor;

// Output fragment color
out vec4 finalColor;

// Camera position for view-dependent effects
uniform vec3 viewPos;

// ============================================================================
// SNOW SHADER - Simplified and balanced
// ============================================================================

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float hash3(vec3 p) {
    return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    value += amplitude * noise(p); amplitude *= 0.5; p *= 2.0;
    value += amplitude * noise(p); amplitude *= 0.5; p *= 2.0;
    value += amplitude * noise(p);
    return value;
}

// Simple sparkle
float sparkle(vec3 worldPos, vec3 viewDir) {
    vec3 sp = worldPos * 15.0;
    vec3 cellId = floor(sp);
    float h = hash3(cellId);
    
    if (h > 0.85) {
        vec3 sparkleNorm = normalize(vec3(
            hash3(cellId + 1.0) * 2.0 - 1.0,
            0.9,
            hash3(cellId + 2.0) * 2.0 - 1.0
        ));
        vec3 lightDir = normalize(vec3(0.5, -1.0, 0.3));
        vec3 halfVec = normalize(-lightDir + viewDir);
        float spec = pow(max(dot(sparkleNorm, halfVec), 0.0), 256.0);
        return spec * (h - 0.85) * 6.67;
    }
    return 0.0;
}

void main() {
    vec3 normal = normalize(fragNormal);
    vec3 viewDir = normalize(viewPos - fragPosition);
    vec3 baseColor = fragColor.rgb;
    
    // Snow detection
    float brightness = dot(baseColor, vec3(0.299, 0.587, 0.114));
    float isSnow = smoothstep(0.5, 0.75, brightness);
    
    // === SURFACE DETAIL (subtle normal perturbation) ===
    vec2 uv = fragWorldPosition.xz * 0.1;
    float nx = (fbm(uv + vec2(0.1, 0.0)) - fbm(uv - vec2(0.1, 0.0))) * 0.15;
    float nz = (fbm(uv + vec2(0.0, 0.1)) - fbm(uv - vec2(0.0, 0.1))) * 0.15;
    vec3 detailNormal = normalize(normal + vec3(nx, 0.0, nz) * isSnow);
    
    // === LIGHTING ===
    vec3 lightDir = normalize(vec3(0.5, -1.0, 0.3));
    vec3 lightColor = vec3(1.0, 0.99, 0.97);
    
    float NdotL = max(dot(detailNormal, -lightDir), 0.0);
    float diffuse = 0.4 + NdotL * 0.6; // 40% ambient, 60% diffuse
    
    // === SUBTLE SHADOW TINT (only in darkest areas) ===
    vec3 shadowTint = vec3(0.92, 0.95, 1.0); // Very slight blue
    vec3 litColor = baseColor * lightColor;
    vec3 shadowColor = baseColor * shadowTint * 0.7;
    
    vec3 color = mix(shadowColor, litColor, diffuse);
    
    // === SUBSURFACE (very subtle) ===
    float VdotL = max(dot(viewDir, lightDir), 0.0);
    float sss = pow(VdotL, 3.0) * 0.08 * isSnow;
    color += vec3(0.95, 0.97, 1.0) * sss;
    
    // === FRESNEL RIM (subtle) ===
    float fresnel = pow(1.0 - max(dot(normal, viewDir), 0.0), 4.0);
    color += vec3(0.9, 0.95, 1.0) * fresnel * 0.1 * isSnow;
    
    // === SPARKLES ===
    if (isSnow > 0.5) {
        float sp = sparkle(fragWorldPosition, viewDir);
        color += vec3(1.0) * sp;
    }
    
    // === SLOPE DARKENING ===
    float slope = 1.0 - normal.y;
    color *= 1.0 - slope * 0.15 * isSnow;
    
    // === SURFACE GRAIN (very subtle brightness variation) ===
    float grain = fbm(fragWorldPosition.xz * 0.5);
    color *= 0.97 + grain * 0.06;
    
    finalColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
